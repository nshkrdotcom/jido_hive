defmodule JidoHiveServer.Collaboration.RoomServer do
  @moduledoc false

  use GenServer

  alias JidoHiveServer.Collaboration.AssignmentBuilders.Basic
  alias JidoHiveServer.Collaboration.DispatchPolicy.Registry, as: PolicyRegistry
  alias JidoHiveServer.Collaboration.{EventReducer, ParticipantSessionRegistry}

  alias JidoHiveServer.Collaboration.Schema.{
    Assignment,
    Contribution,
    Participant,
    RoomEvent,
    RoomSnapshot
  }

  alias JidoHiveServer.Persistence

  def start_link(opts) when is_list(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, opts, name: via(room_id))
  end

  def via(room_id) do
    {:via, Registry, {JidoHiveServer.Collaboration.Registry, room_id}}
  end

  def snapshot(server), do: GenServer.call(server, :snapshot)

  def patch_room(server, attrs) when is_map(attrs),
    do: GenServer.call(server, {:patch_room, attrs})

  def register_participant(server, attrs) when is_map(attrs) do
    GenServer.call(server, {:register_participant, attrs})
  end

  def remove_participant(server, participant_id) when is_binary(participant_id) do
    GenServer.call(server, {:remove_participant, participant_id})
  end

  def submit_contribution(server, attrs) when is_map(attrs) do
    GenServer.call(server, {:submit_contribution, attrs})
  end

  def update_assignment(server, assignment_id, status)
      when is_binary(assignment_id) and is_binary(status) do
    GenServer.call(server, {:update_assignment, assignment_id, status})
  end

  def expire_assignment(server, assignment_id, reason \\ nil)
      when is_binary(assignment_id) do
    GenServer.call(server, {:expire_assignment, assignment_id, reason})
  end

  def dispatch_once(server, opts \\ []) when is_list(opts) do
    GenServer.call(server, {:dispatch_once, opts}, :infinity)
  end

  @impl true
  def init(opts) do
    with %RoomSnapshot{} = snapshot <- Keyword.fetch!(opts, :snapshot),
         {:ok, policy_module} <- PolicyRegistry.fetch_module(snapshot.dispatch.policy_id),
         {:ok, replayed_snapshot} <- replay_post_checkpoint(snapshot, policy_module) do
      {:ok, %{snapshot: replayed_snapshot, policy_module: policy_module}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, {:ok, state.snapshot}, state}
  end

  def handle_call({:patch_room, attrs}, _from, state) do
    with {:ok, requests} <- room_patch_requests(state.snapshot, attrs),
         {:ok, snapshot, events} <- apply_requests(state.snapshot, state.policy_module, requests),
         {:ok, persisted} <- persist_and_broadcast(snapshot, events) do
      {:reply, {:ok, persisted}, %{state | snapshot: persisted}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:register_participant, attrs}, _from, state) do
    attrs =
      attrs
      |> Map.put("room_id", state.snapshot.room.id)
      |> Map.put_new("joined_at", DateTime.utc_now())

    with {:ok, participant} <- Participant.new(attrs),
         {:ok, snapshot, events} <-
           apply_requests(state.snapshot, state.policy_module, [
             {:participant_joined, %{"participant" => Participant.to_map(participant)}}
           ]),
         {:ok, persisted} <- persist_and_broadcast(snapshot, events) do
      {:reply, {:ok, persisted}, %{state | snapshot: persisted}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:remove_participant, participant_id}, _from, state) do
    with {:ok, snapshot, events} <-
           apply_requests(state.snapshot, state.policy_module, [
             {:participant_left, %{"participant_id" => participant_id}}
           ]),
         {:ok, persisted} <- persist_and_broadcast(snapshot, events) do
      {:reply, {:ok, persisted}, %{state | snapshot: persisted}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:submit_contribution, attrs}, _from, state) do
    with {:ok, requests} <- contribution_requests(state.snapshot, attrs),
         {:ok, snapshot, events} <- apply_requests(state.snapshot, state.policy_module, requests),
         {:ok, persisted} <- persist_and_broadcast(snapshot, events) do
      {:reply, {:ok, persisted}, %{state | snapshot: persisted}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:update_assignment, assignment_id, status}, _from, state) do
    with {:ok, requests} <- assignment_update_requests(state.snapshot, assignment_id, status),
         {:ok, snapshot, events} <- apply_requests(state.snapshot, state.policy_module, requests),
         {:ok, persisted} <- persist_and_broadcast(snapshot, events) do
      {:reply, {:ok, persisted}, %{state | snapshot: persisted}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:expire_assignment, assignment_id, reason}, _from, state) do
    with {:ok, snapshot, events} <-
           apply_requests(state.snapshot, state.policy_module, [
             {:assignment_expired,
              %{
                "assignment_id" => assignment_id,
                "reason" => reason,
                "inserted_at" => DateTime.utc_now()
              }}
           ]),
         {:ok, persisted} <- persist_and_broadcast(snapshot, events) do
      {:reply, {:ok, persisted}, %{state | snapshot: persisted}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:dispatch_once, _opts}, _from, state) do
    context = dispatch_context(state.snapshot)

    with {:ok, snapshot, events, result} <-
           dispatch_requests(state.snapshot, state.policy_module, context),
         {:ok, persisted} <- persist_and_broadcast(snapshot, events) do
      {:reply, {:ok, result, persisted}, %{state | snapshot: persisted}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp replay_post_checkpoint(%RoomSnapshot{} = snapshot, policy_module) do
    with {:ok, events} <-
           Persistence.list_room_events_after(
             snapshot.room.id,
             snapshot.replay.checkpoint_event_sequence
           ) do
      {:ok,
       Enum.reduce(events, snapshot, fn event, current_snapshot ->
         apply_event_with_policy(current_snapshot, policy_module, event)
       end)}
    end
  end

  defp room_patch_requests(%RoomSnapshot{} = snapshot, attrs) do
    attrs = Map.drop(attrs, ["room_id", "id"])

    supported_keys = Map.keys(attrs) -- ["name", "phase", "status"]

    cond do
      supported_keys != [] ->
        {:error, :unsupported_room_patch}

      Map.get(attrs, "status") not in [nil, "closed"] ->
        {:error, :unsupported_room_status}

      true ->
        requests =
          []
          |> maybe_append_name_request(snapshot, Map.get(attrs, "name"))
          |> maybe_append_phase_request(snapshot, attrs)
          |> maybe_append_status_request(snapshot, Map.get(attrs, "status"))

        {:ok, requests}
    end
  end

  defp maybe_append_name_request(requests, _snapshot, nil), do: requests

  defp maybe_append_name_request(requests, snapshot, name) when is_binary(name) do
    if String.trim(name) == "" do
      requests
    else
      updated_room = %{snapshot.room | name: String.trim(name), updated_at: DateTime.utc_now()}
      requests ++ [{:room_created, %{"room" => room_map(updated_room)}}]
    end
  end

  defp maybe_append_phase_request(requests, _snapshot, attrs) do
    if Map.has_key?(attrs, "phase") do
      requests ++
        [
          {:room_phase_changed,
           %{"phase" => Map.get(attrs, "phase"), "inserted_at" => DateTime.utc_now()}}
        ]
    else
      requests
    end
  end

  defp maybe_append_status_request(requests, snapshot, "closed") do
    expiration_requests =
      snapshot.assignments
      |> Enum.filter(&(&1.status in ["pending", "active"]))
      |> Enum.map(fn assignment ->
        {:assignment_expired,
         %{
           "assignment_id" => assignment.id,
           "reason" => "room closed",
           "inserted_at" => DateTime.utc_now()
         }}
      end)

    requests ++
      [{:room_status_changed, %{"status" => "closed", "inserted_at" => DateTime.utc_now()}}] ++
      expiration_requests
  end

  defp maybe_append_status_request(requests, _snapshot, _status), do: requests

  defp contribution_requests(%RoomSnapshot{} = snapshot, attrs) do
    contribution =
      attrs
      |> Map.put("room_id", snapshot.room.id)
      |> Map.put_new("id", contribution_id(snapshot))
      |> Map.put_new("meta", %{})
      |> Map.put_new("payload", %{})
      |> Map.put_new("inserted_at", DateTime.utc_now())

    with {:ok, canonical_contribution} <- Contribution.new(contribution),
         :ok <- validate_contribution(snapshot, canonical_contribution) do
      completion_requests =
        assignment_completion_requests(snapshot, canonical_contribution.assignment_id)

      {:ok,
       [
         {:contribution_submitted,
          %{"contribution" => Contribution.to_map(canonical_contribution)}}
       ] ++ completion_requests}
    end
  end

  defp assignment_update_requests(%RoomSnapshot{} = snapshot, assignment_id, "active") do
    case Enum.find(snapshot.assignments, &(&1.id == assignment_id)) do
      nil ->
        {:error, :assignment_not_found}

      %Assignment{} = assignment ->
        updated_assignment = %{assignment | status: "active"}
        {:ok, [{:assignment_created, %{"assignment" => Assignment.to_map(updated_assignment)}}]}
    end
  end

  defp assignment_update_requests(%RoomSnapshot{} = snapshot, assignment_id, "completed") do
    if Enum.any?(snapshot.assignments, &(&1.id == assignment_id)) do
      {:ok,
       [
         {:assignment_completed,
          %{"assignment_id" => assignment_id, "inserted_at" => DateTime.utc_now()}}
       ]}
    else
      {:error, :assignment_not_found}
    end
  end

  defp assignment_update_requests(_snapshot, _assignment_id, _status),
    do: {:error, :unsupported_assignment_status}

  defp dispatch_requests(%RoomSnapshot{} = snapshot, policy_module, context) do
    case policy_module.select(snapshot, context) do
      {:wait, reason, policy_state, room_patch} ->
        requests = materialize_room_patch_requests(snapshot, room_patch)

        with {:ok, next_snapshot, events} <-
               apply_requests(snapshot, policy_module, requests, policy_state) do
          {:ok, next_snapshot, events, {:wait, reason}}
        end

      {:complete, completion, policy_state, room_patch} ->
        requests =
          materialize_room_patch_requests(snapshot, Map.put(room_patch, :status, "completed"))

        with {:ok, next_snapshot, events} <-
               apply_requests(snapshot, policy_module, requests, policy_state) do
          {:ok, next_snapshot, events, {:complete, completion}}
        end

      {:close, reason, policy_state, room_patch} ->
        requests =
          materialize_room_patch_requests(snapshot, Map.put(room_patch, :status, "closed"))

        with {:ok, next_snapshot, events} <-
               apply_requests(snapshot, policy_module, requests, policy_state) do
          {:ok, next_snapshot, events, {:close, reason}}
        end

      {:dispatch, participant_ids, policy_state, room_patch} ->
        dispatch_assignments(
          snapshot,
          policy_module,
          participant_ids,
          policy_state,
          room_patch,
          context
        )
    end
  end

  defp build_assignment_requests(snapshot, participant_ids, context) do
    Enum.reduce_while(participant_ids, {:ok, []}, fn participant_id, {:ok, acc} ->
      case assignment_request(snapshot, participant_id, context) do
        {:ok, request} -> {:cont, {:ok, acc ++ [request]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp dispatch_assignments(
         snapshot,
         policy_module,
         participant_ids,
         policy_state,
         room_patch,
         context
       ) do
    case build_assignment_requests(snapshot, participant_ids, context) do
      {:ok, assignment_requests} ->
        requests = materialize_room_patch_requests(snapshot, room_patch) ++ assignment_requests

        with {:ok, next_snapshot, events} <-
               apply_requests(snapshot, policy_module, requests, policy_state) do
          {:ok, next_snapshot, events, {:dispatch, created_assignment_ids(events)}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp created_assignment_ids(events) do
    events
    |> Enum.filter(&(&1.type == :assignment_created))
    |> Enum.map(fn event ->
      event.data
      |> Map.get("assignment", event.data)
      |> Map.get("id")
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp assignment_request(%RoomSnapshot{} = snapshot, participant_id, context) do
    with %Participant{} = participant <-
           Enum.find(snapshot.participants, &(&1.id == participant_id)),
         {:ok, payload} <- assignment_builder(snapshot).build(snapshot, participant, context) do
      assignment = %{
        "id" => assignment_id(snapshot),
        "room_id" => snapshot.room.id,
        "participant_id" => participant.id,
        "payload" => payload,
        "status" => "pending",
        "deadline" => deadline(snapshot),
        "inserted_at" => DateTime.utc_now(),
        "meta" => %{"participant_meta" => participant.meta}
      }

      {:ok, {:assignment_created, %{"assignment" => assignment}}}
    else
      nil -> {:error, :participant_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_requests(snapshot, policy_module, requests, override_policy_state \\ nil)
       when is_list(requests) do
    working_snapshot =
      case override_policy_state do
        nil -> snapshot
        policy_state -> put_in(snapshot.dispatch.policy_state, policy_state)
      end

    Enum.reduce_while(requests, {:ok, working_snapshot, []}, fn {type, data},
                                                                {:ok, current_snapshot,
                                                                 acc_events} ->
      reduce_request(policy_module, type, data, current_snapshot, acc_events)
    end)
  end

  defp reduce_request(policy_module, type, data, current_snapshot, acc_events) do
    case build_event(current_snapshot, type, data) do
      {:ok, event} ->
        case apply_event_request(current_snapshot, policy_module, event) do
          {:ok, next_snapshot, events} -> {:cont, {:ok, next_snapshot, acc_events ++ events}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp apply_event_request(snapshot, policy_module, %RoomEvent{} = event) do
    next_snapshot = apply_event_with_policy(snapshot, policy_module, event)
    room_patch = Map.get(next_snapshot.dispatch.policy_state, :pending_room_patch, %{})

    next_snapshot =
      if room_patch == %{} do
        next_snapshot
      else
        put_in(next_snapshot.dispatch.policy_state.pending_room_patch, %{})
      end

    patch_requests = materialize_room_patch_requests(next_snapshot, room_patch)

    case apply_requests(next_snapshot, policy_module, patch_requests) do
      {:ok, final_snapshot, patch_events} ->
        {:ok, final_snapshot, [event] ++ patch_events}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_event_with_policy(snapshot, policy_module, %RoomEvent{} = event) do
    reduced_snapshot = EventReducer.apply_event(snapshot, event)
    context = dispatch_context(reduced_snapshot)

    {:ok, policy_state, room_patch} =
      policy_module.handle_event(
        event,
        reduced_snapshot,
        reduced_snapshot.dispatch.policy_state,
        context
      )

    reduced_snapshot
    |> put_in(
      [Access.key(:dispatch), Access.key(:policy_state)],
      Map.put(policy_state, :pending_room_patch, room_patch)
    )
  end

  defp build_event(%RoomSnapshot{} = snapshot, type, data) do
    RoomEvent.new(%{
      "id" => event_id(snapshot),
      "room_id" => snapshot.room.id,
      "sequence" => snapshot.clocks.next_event_sequence,
      "type" => type,
      "data" => data,
      "inserted_at" => DateTime.utc_now()
    })
  end

  defp persist_and_broadcast(snapshot, events) when events == [] do
    {:ok, snapshot}
  end

  defp persist_and_broadcast(%RoomSnapshot{} = snapshot, events) when is_list(events) do
    checkpoint =
      events
      |> List.last()
      |> case do
        %RoomEvent{sequence: sequence} -> sequence
        _other -> snapshot.replay.checkpoint_event_sequence
      end

    snapshot = put_in(snapshot.replay.checkpoint_event_sequence, checkpoint)

    with {:ok, persisted} <-
           Persistence.persist_room_transition(snapshot.room.id, events, snapshot) do
      Enum.each(events, &broadcast_room_event(snapshot.room.id, &1))
      Enum.each(events, &deliver_assignment_offer_if_needed(snapshot.room.id, &1))
      {:ok, persisted}
    end
  end

  defp materialize_room_patch_requests(_snapshot, room_patch) when room_patch in [%{}, nil],
    do: []

  defp materialize_room_patch_requests(snapshot, room_patch) when is_map(room_patch) do
    []
    |> maybe_patch_status(snapshot, Map.get(room_patch, :status))
    |> maybe_patch_phase(snapshot, room_patch)
  end

  defp maybe_patch_status(requests, _snapshot, nil), do: requests

  defp maybe_patch_status(requests, snapshot, status) do
    if snapshot.room.status == status do
      requests
    else
      requests ++
        [{:room_status_changed, %{"status" => status, "inserted_at" => DateTime.utc_now()}}]
    end
  end

  defp maybe_patch_phase(requests, snapshot, room_patch) do
    if Map.has_key?(room_patch, :phase) do
      phase = Map.get(room_patch, :phase)

      if snapshot.room.phase == phase do
        requests
      else
        requests ++
          [{:room_phase_changed, %{"phase" => phase, "inserted_at" => DateTime.utc_now()}}]
      end
    else
      requests
    end
  end

  defp validate_contribution(snapshot, %Contribution{} = contribution) do
    case contribution_validator(snapshot) do
      nil -> :ok
      validator -> validator.validate(contribution, snapshot.room)
    end
  end

  defp contribution_validator(snapshot) do
    resolve_module(get_in(snapshot.room.config, ["contribution_validator"]))
  end

  defp assignment_builder(snapshot) do
    snapshot.room.config
    |> get_in(["assignment_builder"])
    |> resolve_module()
    |> case do
      nil -> Basic
      module -> module
    end
  end

  defp resolve_module(module) when is_atom(module), do: module

  defp resolve_module(module) when is_binary(module) do
    String.to_existing_atom(module)
  rescue
    ArgumentError -> nil
  end

  defp resolve_module(_module), do: nil

  defp dispatch_context(snapshot) do
    %{
      availability: ParticipantSessionRegistry.availability(snapshot.room.id),
      policy_state: snapshot.dispatch.policy_state,
      now: DateTime.utc_now()
    }
  end

  defp assignment_open?(snapshot, assignment_id) do
    Enum.any?(
      snapshot.assignments,
      &(&1.id == assignment_id and &1.status in ["pending", "active"])
    )
  end

  defp assignment_completion_requests(_snapshot, assignment_id)
       when not is_binary(assignment_id),
       do: []

  defp assignment_completion_requests(snapshot, assignment_id) do
    if assignment_open?(snapshot, assignment_id) do
      [
        {:assignment_completed,
         %{"assignment_id" => assignment_id, "inserted_at" => DateTime.utc_now()}}
      ]
    else
      []
    end
  end

  defp deadline(snapshot) do
    timeout_ms = get_in(snapshot.room.config, ["assignment_timeout_ms"]) || 60_000
    DateTime.add(DateTime.utc_now(), timeout_ms, :millisecond)
  end

  defp event_id(snapshot), do: "evt-#{snapshot.room.id}-#{snapshot.clocks.next_event_sequence}"
  defp assignment_id(snapshot), do: "asg-#{snapshot.clocks.next_assignment_seq}"
  defp contribution_id(snapshot), do: "ctrb-#{snapshot.clocks.next_contribution_seq}"

  defp room_map(room) do
    %{
      id: room.id,
      name: room.name,
      status: room.status,
      phase: room.phase,
      config: room.config,
      inserted_at: room.inserted_at,
      updated_at: room.updated_at
    }
  end

  defp broadcast_room_event(room_id, %RoomEvent{} = event) do
    JidoHiveServerWeb.Endpoint.broadcast("room:#{room_id}", "room.event", %{
      "data" => room_event_payload(event)
    })
  end

  defp room_event_payload(%RoomEvent{} = event) do
    %{
      "id" => event.id,
      "room_id" => event.room_id,
      "sequence" => event.sequence,
      "type" => Atom.to_string(event.type),
      "data" => normalize(event.data),
      "inserted_at" => DateTime.to_iso8601(event.inserted_at)
    }
  end

  defp deliver_assignment_offer_if_needed(_room_id, %RoomEvent{type: type})
       when type != :assignment_created, do: :ok

  defp deliver_assignment_offer_if_needed(room_id, %RoomEvent{data: data}) do
    assignment_data = Map.get(data, "assignment", data)

    with {:ok, assignment} <- Assignment.new(assignment_data) do
      ParticipantSessionRegistry.deliver_assignment_offer(room_id, assignment)
    end
  end

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(%_{} = value), do: value |> Map.from_struct() |> normalize()

  defp normalize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value), do: value
end
