defmodule JidoHiveServer.Collaboration do
  @moduledoc false

  alias JidoHiveServer.Collaboration.ContextGraph
  alias JidoHiveServer.Collaboration.DispatchPolicy.Registry, as: PolicyRegistry
  alias JidoHiveServer.Collaboration.RoomServer
  alias JidoHiveServer.Collaboration.Schema.{Assignment, Participant, RoomEvent}
  alias JidoHiveServer.Collaboration.SnapshotProjection
  alias JidoHiveServer.Persistence
  alias JidoHiveServer.Publications
  alias JidoHiveServer.RemoteExec

  def create_room(attrs) when is_map(attrs) do
    room_id = value(attrs, "room_id")
    brief = value(attrs, "brief")
    rules = list_value(attrs, "rules")
    dispatch_policy_id = value(attrs, "dispatch_policy_id") || "round_robin/v2"
    dispatch_policy_config = map_value(attrs, "dispatch_policy_config")
    context_config = map_value(attrs, "context_config")

    with true <-
           (is_binary(room_id) and String.trim(room_id) != "") or {:error, :room_id_required},
         true <- (is_binary(brief) and String.trim(brief) != "") or {:error, :brief_required},
         {:ok, participants} <-
           normalize_participants(
             Map.get(attrs, :participants) || Map.get(attrs, "participants", [])
           ),
         {:ok, policy_module} <- PolicyRegistry.fetch_module(dispatch_policy_id),
         snapshot <-
           base_snapshot(
             room_id,
             brief,
             rules,
             participants,
             context_config,
             dispatch_policy_id,
             dispatch_policy_config,
             policy_module
           ),
         :ok <- replace_room_server(room_id),
         :ok <- Persistence.delete_room_events(room_id),
         {:ok, _snapshot} <- Persistence.persist_room_snapshot(snapshot),
         :ok <- append_room_created_event(snapshot),
         {:ok, _pid} <- ensure_room_server(snapshot) do
      fetch_room(room_id)
    else
      false -> {:error, :invalid_room}
      {:error, _reason} = error -> error
    end
  end

  def fetch_room(room_id) when is_binary(room_id) do
    with {:ok, snapshot} <- load_room_snapshot(room_id),
         {:ok, _pid} <- ensure_room_server(snapshot),
         [{pid, _value}] <- Registry.lookup(JidoHiveServer.Collaboration.Registry, room_id),
         {:ok, current} <- RoomServer.snapshot(pid) do
      {:ok, current}
    else
      [] -> {:error, :room_not_found}
      {:error, _} = error -> error
    end
  end

  def receive_contribution(%{"room_id" => room_id} = payload),
    do: receive_contribution_internal(room_id, payload)

  def receive_contribution(%{room_id: room_id} = payload),
    do: receive_contribution_internal(room_id, payload)

  def receive_contribution(_payload), do: {:error, :invalid_payload}

  def record_manual_contribution(room_id, attrs) when is_binary(room_id) and is_map(attrs) do
    contribution =
      attrs
      |> put_default("room_id", room_id)
      |> put_default("participant_id", value(attrs, "participant_id") || "human")
      |> put_default("participant_role", value(attrs, "participant_role") || "reviewer")
      |> put_default("participant_kind", value(attrs, "participant_kind") || "human")
      |> put_default("contribution_type", value(attrs, "contribution_type") || "perspective")
      |> put_default("authority_level", value(attrs, "authority_level") || "binding")
      |> put_default("summary", value(attrs, "summary") || "manual contribution")
      |> put_default("context_objects", [])
      |> put_default("execution", %{"status" => "completed"})
      |> put_default("status", "completed")
      |> put_default("schema_version", "jido_hive/contribution.submit.v1")

    receive_contribution(contribution)
  end

  def run_first_slice(room_id) when is_binary(room_id) do
    run_room(room_id, max_assignments: 1)
  end

  def run_room(room_id, opts \\ []) when is_binary(room_id) and is_list(opts) do
    assignment_timeout_ms =
      Keyword.get(opts, :assignment_timeout_ms, assignment_wait_timeout_ms())

    with {:ok, snapshot} <- fetch_room(room_id) do
      completed_slots = snapshot.dispatch_state.completed_slots || 0
      total_slots = snapshot.dispatch_state.total_slots || 0
      requested_assignments = Keyword.get(opts, :max_assignments, total_slots)
      target_completed_slots = min(completed_slots + requested_assignments, total_slots)
      do_run_room(room_id, snapshot, target_completed_slots, assignment_timeout_ms)
    end
  end

  def publication_plan(room_id) when is_binary(room_id) do
    with {:ok, snapshot} <- fetch_room(room_id) do
      {:ok, Publications.build_plan(snapshot)}
    end
  end

  def publication_runs(room_id) when is_binary(room_id) do
    with {:ok, _snapshot} <- fetch_room(room_id) do
      {:ok, Persistence.list_publication_runs(room_id)}
    end
  end

  def execute_publications(room_id, attrs) when is_binary(room_id) and is_map(attrs) do
    with {:ok, snapshot} <- fetch_room(room_id) do
      Publications.execute(snapshot, attrs)
    end
  end

  def list_context_objects(room_id) when is_binary(room_id) do
    with {:ok, snapshot} <- fetch_room(room_id) do
      {:ok, Enum.map(snapshot.context_objects, &decorate_context_object(&1, snapshot))}
    end
  end

  def fetch_context_object(room_id, context_id)
      when is_binary(room_id) and is_binary(context_id) do
    with {:ok, snapshot} <- fetch_room(room_id),
         context_object when not is_nil(context_object) <-
           Enum.find(snapshot.context_objects, &(&1.context_id == context_id)) do
      {:ok, decorate_context_object(context_object, snapshot)}
    else
      nil -> {:error, :context_object_not_found}
      {:error, _} = error -> error
    end
  end

  defp receive_contribution_internal(room_id, payload) do
    with {:ok, snapshot} <- load_room_snapshot(room_id),
         {:ok, _pid} <- ensure_room_server(snapshot),
         [{pid, _value}] <- Registry.lookup(JidoHiveServer.Collaboration.Registry, room_id),
         {:ok, next_snapshot} <- RoomServer.record_contribution(pid, %{"contribution" => payload}) do
      {:ok, next_snapshot}
    else
      [] -> {:error, :room_not_found}
      {:error, _} = error -> error
    end
  end

  defp do_run_room(room_id, snapshot, target_completed_slots, _timeout_ms)
       when snapshot.dispatch_state.completed_slots >= target_completed_slots,
       do: fetch_room(room_id)

  defp do_run_room(room_id, snapshot, target_completed_slots, assignment_timeout_ms) do
    case next_action(snapshot, available_target_ids()) do
      {:complete, _status} ->
        fetch_room(room_id)

      {:awaiting_authority, status} ->
        set_room_status(room_id, status)

      {:blocked, status} ->
        set_room_status(room_id, status)

      {:ok, assignment_attrs} ->
        with {:ok, _result} <-
               run_assignment(room_id, snapshot, assignment_attrs, assignment_timeout_ms),
             {:ok, refreshed} <- fetch_room(room_id) do
          do_run_room(room_id, refreshed, target_completed_slots, assignment_timeout_ms)
        end
    end
  end

  defp run_assignment(room_id, snapshot, assignment_attrs, assignment_timeout_ms) do
    assignment_id = "asn-#{snapshot.next_assignment_seq}"
    server = RoomServer.via(room_id)

    with {:ok, target} <- RemoteExec.fetch_target(assignment_attrs.target_id),
         {:ok, session} <- session_request(target),
         {:ok, assignment} <-
           Assignment.new(
             Map.merge(assignment_attrs, %{
               assignment_id: assignment_id,
               room_id: room_id,
               session: session
             })
           ),
         assignment_map <- Map.from_struct(assignment),
         {:ok, _opened} <- RoomServer.open_assignment(server, %{"assignment" => assignment_map}),
         :ok <- RemoteExec.dispatch_assignment(assignment_map.target_id, assignment_map),
         {:ok, result_assignment} <-
           wait_for_assignment(room_id, assignment_id, assignment_timeout_ms) do
      assignment_result(result_assignment)
    else
      {:error, :unknown_target} ->
        RoomServer.abandon_assignment(server, %{
          "assignment_id" => assignment_id,
          "reason" => "target unavailable before dispatch"
        })

        {:ok, :abandoned}

      {:error, :assignment_timeout} ->
        RoomServer.abandon_assignment(server, %{
          "assignment_id" => assignment_id,
          "reason" => "assignment timed out before a client contribution was received"
        })

        {:ok, :abandoned}

      {:error, _reason} = error ->
        error
    end
  end

  defp assignment_result(%{status: "completed"}), do: {:ok, :completed}
  defp assignment_result(%{status: "failed"}), do: {:ok, :failed}
  defp assignment_result(%{status: "abandoned"}), do: {:ok, :abandoned}

  defp session_request(target) do
    {:ok,
     %{
       "runtime_driver" => target.runtime_driver || "asm",
       "provider" => target.provider || "codex",
       "workspace_root" => target.workspace_root,
       "execution_surface" => target.execution_surface,
       "execution_environment" => target.execution_environment,
       "provider_options" => target.provider_options
     }
     |> Enum.reject(fn {_key, value} -> is_nil(value) end)
     |> Map.new()}
  end

  defp next_action(snapshot, available_target_ids) do
    case PolicyRegistry.fetch_module(snapshot.dispatch_policy_id) do
      {:ok, module} -> module.next_action(snapshot, available_target_ids)
      {:error, :unknown_policy} -> {:blocked, "failed"}
    end
  end

  defp set_room_status(room_id, status) do
    with {:ok, _snapshot} <-
           RoomServer.set_runtime_state(RoomServer.via(room_id), %{"status" => status}) do
      fetch_room(room_id)
    end
  end

  defp wait_for_assignment(room_id, assignment_id, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_assignment(room_id, assignment_id, deadline)
  end

  defp do_wait_for_assignment(room_id, assignment_id, deadline_ms) do
    case fetch_room(room_id) do
      {:ok, snapshot} ->
        snapshot
        |> find_assignment_result(assignment_id)
        |> wait_or_timeout(room_id, assignment_id, deadline_ms)

      {:error, _} = error ->
        error
    end
  end

  defp find_assignment_result(snapshot, assignment_id) do
    Enum.find(
      snapshot.assignments,
      &(&1.assignment_id == assignment_id and &1.status in ["completed", "failed", "abandoned"])
    )
  end

  defp wait_or_timeout(nil, room_id, assignment_id, deadline_ms) do
    remaining_ms = deadline_ms - System.monotonic_time(:millisecond)

    if remaining_ms <= 0 do
      {:error, :assignment_timeout}
    else
      Process.sleep(min(assignment_wait_poll_ms(), remaining_ms))
      do_wait_for_assignment(room_id, assignment_id, deadline_ms)
    end
  end

  defp wait_or_timeout(assignment, _room_id, _assignment_id, _deadline_ms), do: {:ok, assignment}

  defp available_target_ids do
    RemoteExec.list_targets()
    |> Enum.map(& &1.target_id)
  end

  defp normalize_participants(participants) when is_list(participants) do
    participants
    |> Enum.map(&Participant.new/1)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, participant}, {:ok, acc} -> {:cont, {:ok, acc ++ [Map.from_struct(participant)]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
  end

  defp base_snapshot(
         room_id,
         brief,
         rules,
         participants,
         context_config,
         dispatch_policy_id,
         dispatch_policy_config,
         policy_module
       ) do
    snapshot = %{
      room_id: room_id,
      session_id: "room-session-#{room_id}",
      brief: brief,
      rules: rules,
      status: "idle",
      participants: participants,
      current_assignment: %{},
      assignments: [],
      context_objects: [],
      contributions: [],
      context_config: context_config,
      context_graph: %{outgoing: %{}, incoming: %{}},
      context_annotations: %{},
      dispatch_policy_id: dispatch_policy_id,
      dispatch_policy_config: dispatch_policy_config,
      dispatch_state: %{},
      next_context_seq: 1,
      next_assignment_seq: 1,
      next_contribution_seq: 1
    }

    snapshot
    |> Map.put(:dispatch_state, policy_module.init_state(snapshot))
    |> SnapshotProjection.project()
  end

  defp load_room_snapshot(room_id) do
    case Registry.lookup(JidoHiveServer.Collaboration.Registry, room_id) do
      [{pid, _value}] -> RoomServer.snapshot(pid)
      [] -> Persistence.fetch_room_snapshot(room_id)
    end
  end

  defp ensure_room_server(snapshot) do
    spec = {RoomServer, room_id: snapshot.room_id, snapshot: snapshot}

    case DynamicSupervisor.start_child(JidoHiveServer.Collaboration.RoomSupervisor, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, {:already_present, _}} -> {:ok, RoomServer.via(snapshot.room_id)}
      other -> other
    end
  end

  defp replace_room_server(room_id) do
    case Registry.lookup(JidoHiveServer.Collaboration.Registry, room_id) do
      [{pid, _value}] ->
        case DynamicSupervisor.terminate_child(JidoHiveServer.Collaboration.RoomSupervisor, pid) do
          :ok -> :ok
          {:error, :not_found} -> :ok
        end

      [] ->
        :ok
    end
  end

  defp append_room_created_event(snapshot) do
    {:ok, event} =
      RoomEvent.new(%{
        event_id: unique_id("evt"),
        room_id: snapshot.room_id,
        type: :room_created,
        payload: snapshot,
        recorded_at: DateTime.utc_now()
      })

    Persistence.append_room_events(snapshot.room_id, [event])
  end

  defp assignment_wait_timeout_ms do
    Application.get_env(:jido_hive_server, :assignment_wait_timeout_ms, 180_000)
  end

  defp assignment_wait_poll_ms do
    Application.get_env(:jido_hive_server, :assignment_wait_poll_ms, 250)
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp map_value(map, key) do
    case value(map, key) do
      %{} = value -> value
      _other -> %{}
    end
  end

  defp list_value(map, key) do
    case value(map, key) do
      list when is_list(list) -> list
      _other -> []
    end
  end

  defp put_default(map, key, value) do
    map
    |> Map.put_new(key, value)
    |> maybe_put_new_atom_key(key, value)
  end

  defp maybe_put_new_atom_key(map, key, value) when is_binary(key) do
    case existing_atom_key(key) do
      nil -> map
      atom_key -> Map.put_new(map, atom_key, value)
    end
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp decorate_context_object(context_object, snapshot) do
    decorated =
      case Map.get(snapshot, :context_annotations, %{})[context_object.context_id] do
        nil -> context_object
        annotation -> Map.put(context_object, :derived, annotation)
      end

    Map.put(decorated, :adjacency, ContextGraph.adjacency(snapshot, context_object.context_id))
  end
end
