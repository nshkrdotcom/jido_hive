defmodule JidoHiveServer.Collaboration do
  @moduledoc false

  alias JidoHiveServer.Collaboration.{Envelope, ExecutionPlan, Referee}
  alias JidoHiveServer.Collaboration.RoomServer
  alias JidoHiveServer.Persistence
  alias JidoHiveServer.Publications
  alias JidoHiveServer.RemoteExec
  alias JidoHiveServer.Runtime

  def create_room(attrs) when is_map(attrs) do
    :ok = Runtime.ensure_instance()

    room_id = Map.get(attrs, :room_id) || Map.get(attrs, "room_id")
    brief = Map.get(attrs, :brief) || Map.get(attrs, "brief")
    rules = Map.get(attrs, :rules) || Map.get(attrs, "rules") || []

    participants =
      attrs
      |> Map.get(:participants, Map.get(attrs, "participants", []))
      |> Enum.map(&normalize_map_keys/1)

    with {:ok, execution_plan} <- ExecutionPlan.new(participants),
         snapshot <- %{
           room_id: room_id,
           session_id: Map.get(attrs, :session_id, "room-session-#{room_id}"),
           brief: brief,
           rules: rules,
           participants: participants,
           turns: [],
           context_entries: [],
           disputes: [],
           current_turn: %{},
           execution_plan: execution_plan,
           status: "idle",
           phase: "idle",
           round: 0,
           next_entry_seq: 1,
           next_dispute_seq: 1
         },
         :ok <- replace_room_server(room_id),
         {:ok, _snapshot} <- Persistence.persist_room_snapshot(snapshot),
         {:ok, _pid} <- ensure_room_server(snapshot) do
      fetch_room(room_id)
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

  def receive_result(%{"room_id" => room_id} = payload) do
    with {:ok, snapshot} <- load_room_snapshot(room_id),
         {:ok, _pid} <- ensure_room_server(snapshot),
         [{pid, _value}] <- Registry.lookup(JidoHiveServer.Collaboration.Registry, room_id),
         {:ok, snapshot} <- RoomServer.apply_result(pid, payload) do
      {:ok, snapshot}
    else
      [] -> {:error, :room_not_found}
      {:error, _} = error -> error
    end
  end

  def run_first_slice(room_id) when is_binary(room_id) do
    run_room(room_id, max_turns: 3)
  end

  def run_room(room_id, opts \\ []) when is_binary(room_id) and is_list(opts) do
    turn_timeout_ms = Keyword.get(opts, :turn_timeout_ms, turn_wait_timeout_ms())

    with {:ok, snapshot} <- fetch_room(room_id) do
      max_turns =
        opts
        |> Keyword.get_lazy(:max_turns, fn ->
          snapshot.execution_plan
          |> Map.get(:planned_turn_count, 3)
        end)

      target_completed_turn_count =
        max_turns
        |> then(&min(&1, snapshot.execution_plan.planned_turn_count))
        |> then(&max(&1, 0))
        |> Kernel.+(snapshot.execution_plan.completed_turn_count)
        |> min(snapshot.execution_plan.planned_turn_count)

      do_run_room(room_id, snapshot, target_completed_turn_count, turn_timeout_ms)
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

  defp do_run_room(room_id, snapshot, target_completed_turn_count, turn_timeout_ms)

  defp do_run_room(
         room_id,
         %{execution_plan: %{completed_turn_count: completed_turn_count}},
         target_completed_turn_count,
         _turn_timeout_ms
       )
       when completed_turn_count >= target_completed_turn_count,
       do: fetch_room(room_id)

  defp do_run_room(room_id, snapshot, target_completed_turn_count, turn_timeout_ms) do
    case Referee.next_assignment(snapshot, available_target_ids()) do
      :halt ->
        fetch_room(room_id)

      {:error, :no_available_participants} ->
        block_room(room_id, snapshot)

      {:ok, assignment} ->
        with {:ok, _} <- run_turn(room_id, snapshot, assignment, turn_timeout_ms),
             {:ok, refreshed} <- fetch_room(room_id) do
          continue_room(room_id, refreshed, target_completed_turn_count, turn_timeout_ms)
        end
    end
  end

  defp continue_room(
         _room_id,
         %{status: "failed"} = snapshot,
         _target_completed_turn_count,
         _turn_timeout_ms
       ),
       do: {:ok, snapshot}

  defp continue_room(
         _room_id,
         %{status: "blocked"} = snapshot,
         _target_completed_turn_count,
         _turn_timeout_ms
       ),
       do: {:ok, snapshot}

  defp continue_room(
         _room_id,
         %{execution_plan: %{completed_turn_count: completed_turn_count}} = snapshot,
         target_completed_turn_count,
         _turn_timeout_ms
       )
       when completed_turn_count >= target_completed_turn_count,
       do: {:ok, snapshot}

  defp continue_room(room_id, snapshot, target_completed_turn_count, turn_timeout_ms) do
    case Referee.next_assignment(snapshot, available_target_ids()) do
      :halt -> {:ok, snapshot}
      {:error, :no_available_participants} -> block_room(room_id, snapshot)
      {:ok, _next} -> do_run_room(room_id, snapshot, target_completed_turn_count, turn_timeout_ms)
    end
  end

  defp run_turn(room_id, snapshot, assignment, turn_timeout_ms) do
    job_id = unique_id("job")
    server = RoomServer.via(room_id)

    with {:ok, target} <- RemoteExec.fetch_target(assignment.target_id),
         true <- target_online?(target),
         envelope <- Envelope.build(snapshot, Map.put(assignment, :job_id, job_id)),
         session <- session_request(target),
         {:ok, _opened} <-
           RoomServer.open_turn(server, %{
             "job_id" => job_id,
             "plan_slot_index" => assignment.plan_slot_index,
             "participant_id" => assignment.participant_id,
             "participant_role" => assignment.participant_role,
             "target_id" => assignment.target_id,
             "capability_id" => assignment.capability_id,
             "phase" => assignment.phase,
             "objective" => assignment.objective,
             "round" => assignment.round,
             "session" => session,
             "collaboration_envelope" => envelope
           }) do
      dispatch_and_wait_for_turn(
        room_id,
        assignment,
        job_id,
        session,
        envelope,
        turn_timeout_ms,
        server
      )
    else
      false ->
        {:ok, :abandoned}

      {:error, _} = error ->
        error
    end
  end

  defp block_room(room_id, snapshot) do
    with {:ok, _snapshot} <-
           RoomServer.set_runtime_state(RoomServer.via(room_id), %{
             "status" => "blocked",
             "phase" => Referee.phase(snapshot)
           }) do
      fetch_room(room_id)
    end
  end

  defp dispatch_and_wait_for_turn(
         room_id,
         assignment,
         job_id,
         session,
         envelope,
         turn_timeout_ms,
         server
       ) do
    with :ok <- dispatch_turn(room_id, assignment, job_id, session, envelope),
         {:ok, turn} <- wait_for_turn(room_id, job_id, turn_timeout_ms) do
      turn_result(turn)
    else
      {:error, reason} -> abandon_turn(server, job_id, reason)
    end
  end

  defp dispatch_turn(room_id, assignment, job_id, session, envelope) do
    RemoteExec.dispatch_job(assignment.target_id, %{
      "job_id" => job_id,
      "room_id" => room_id,
      "participant_id" => assignment.participant_id,
      "participant_role" => assignment.participant_role,
      "capability_id" => assignment.capability_id,
      "target_id" => assignment.target_id,
      "session" => session,
      "collaboration_envelope" => envelope
    })
  end

  defp turn_result(%{status: :completed}), do: {:ok, :completed}
  defp turn_result(%{status: :failed}), do: {:ok, :failed}

  defp abandon_turn(server, job_id, :turn_timeout) do
    {:ok, _snapshot} =
      RoomServer.abandon_turn(server, %{
        "job_id" => job_id,
        "reason" => "turn timed out before a client result was received"
      })

    {:ok, :abandoned}
  end

  defp abandon_turn(server, job_id, :unknown_target) do
    {:ok, _snapshot} =
      RoomServer.abandon_turn(server, %{
        "job_id" => job_id,
        "reason" => "target went offline before dispatch completed"
      })

    {:ok, :abandoned}
  end

  defp available_target_ids do
    RemoteExec.list_targets()
    |> Enum.map(& &1.target_id)
  end

  defp target_online?(target) do
    case Map.get(target, :status) do
      nil -> true
      "online" -> true
      _other -> false
    end
  end

  defp session_request(target) do
    %{
      "runtime_driver" => target.runtime_driver || "asm",
      "provider" => target.provider || "codex",
      "workspace_root" => target.workspace_root
    }
  end

  defp wait_for_turn(room_id, job_id, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_turn(room_id, job_id, deadline)
  end

  defp do_wait_for_turn(room_id, job_id, deadline_ms) do
    case fetch_room(room_id) do
      {:ok, snapshot} ->
        snapshot
        |> find_turn_result(job_id)
        |> wait_or_timeout(room_id, job_id, deadline_ms)

      {:error, _} = error ->
        error
    end
  end

  defp find_turn_result(snapshot, job_id) do
    Enum.find(snapshot.turns, &(&1.job_id == job_id and &1.status in [:completed, :failed]))
  end

  defp wait_or_timeout(nil, room_id, job_id, deadline_ms) do
    remaining_ms = deadline_ms - System.monotonic_time(:millisecond)

    if remaining_ms <= 0 do
      {:error, :turn_timeout}
    else
      Process.sleep(min(turn_wait_poll_ms(), remaining_ms))
      do_wait_for_turn(room_id, job_id, deadline_ms)
    end
  end

  defp wait_or_timeout(turn, _room_id, _job_id, _deadline_ms), do: {:ok, turn}

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

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp turn_wait_timeout_ms do
    Application.get_env(:jido_hive_server, :turn_wait_timeout_ms, 180_000)
  end

  defp turn_wait_poll_ms do
    Application.get_env(:jido_hive_server, :turn_wait_poll_ms, 250)
  end

  defp normalize_map_keys(value) when is_map(value) do
    Enum.into(value, %{}, fn
      {key, nested} when is_binary(key) -> {String.to_atom(key), nested}
      {key, nested} -> {key, nested}
    end)
  end

  defp normalize_map_keys(value), do: value
end
