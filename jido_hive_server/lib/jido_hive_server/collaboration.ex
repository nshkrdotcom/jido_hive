defmodule JidoHiveServer.Collaboration do
  @moduledoc false

  alias JidoHiveServer.Collaboration.DispatchPolicies.RoundRobin
  alias JidoHiveServer.Collaboration.DispatchPolicy.Registry, as: PolicyRegistry
  alias JidoHiveServer.Collaboration.{EventReducer, ParticipantSessionRegistry, RoomServer}
  alias JidoHiveServer.Collaboration.Schema.{Participant, Room, RoomEvent, RoomSnapshot}
  alias JidoHiveServer.Persistence

  @spec list_rooms(keyword()) :: {:ok, [RoomSnapshot.t()]} | {:error, term()}
  def list_rooms(opts \\ []) do
    Persistence.list_rooms(opts)
  end

  @spec create_room(map()) :: {:ok, RoomSnapshot.t()} | {:error, term()}
  def create_room(attrs) when is_map(attrs) do
    room_id = string_value(attrs, "id") || generated_room_id()
    name = string_value(attrs, "name")
    phase = value(attrs, "phase")
    config = map_value(attrs, "config")
    participants_attrs = list_value(attrs, "participants")
    now = DateTime.utc_now()

    with {:ok, room} <-
           Room.new(%{
             "id" => room_id,
             "name" => name,
             "status" => "waiting",
             "phase" => phase,
             "config" => config,
             "inserted_at" => now,
             "updated_at" => now
           }),
         {:ok, participants} <- build_participants(room_id, participants_attrs),
         policy_id <- Map.get(config, "dispatch_policy", RoundRobin.id()),
         {:ok, policy_module} <- PolicyRegistry.fetch_module(policy_id),
         provisional_snapshot <- %RoomSnapshot{
           RoomSnapshot.initial(room, policy_id, %{})
           | participants: participants
         },
         {:ok, policy_state, room_patch} <- policy_module.init(provisional_snapshot, %{}),
         initial_snapshot <- put_in(provisional_snapshot.dispatch.policy_state, policy_state),
         requests <- initial_room_requests(room, participants, room_patch),
         {:ok, snapshot, events} <-
           apply_initial_requests(initial_snapshot, policy_module, requests),
         :ok <- replace_room_server(room_id),
         :ok <- Persistence.delete_room_events(room_id),
         {:ok, persisted} <-
           Persistence.persist_room_transition(
             room_id,
             events,
             finalize_checkpoint(snapshot, events)
           ),
         {:ok, _pid} <- ensure_room_server(persisted) do
      {:ok, persisted}
    end
  end

  @spec fetch_room_snapshot(String.t()) :: {:ok, RoomSnapshot.t()} | {:error, term()}
  def fetch_room_snapshot(room_id) when is_binary(room_id) do
    with {:ok, snapshot} <- Persistence.fetch_room_snapshot(room_id),
         {:ok, pid} <- ensure_room_server(snapshot) do
      RoomServer.snapshot(pid)
    end
  end

  @spec patch_room(String.t(), map()) :: {:ok, RoomSnapshot.t()} | {:error, term()}
  def patch_room(room_id, attrs) when is_binary(room_id) and is_map(attrs) do
    with {:ok, server} <- fetch_room_server(room_id), do: RoomServer.patch_room(server, attrs)
  end

  @spec close_room(String.t()) :: {:ok, RoomSnapshot.t()} | {:error, term()}
  def close_room(room_id) when is_binary(room_id) do
    with {:ok, snapshot} <- patch_room(room_id, %{"status" => "closed"}) do
      ParticipantSessionRegistry.disconnect_room(room_id)
      {:ok, snapshot}
    end
  end

  @spec list_participants(String.t()) :: {:ok, [Participant.t()]} | {:error, term()}
  def list_participants(room_id) when is_binary(room_id) do
    with {:ok, snapshot} <- fetch_room_snapshot(room_id) do
      {:ok, snapshot.participants}
    end
  end

  @spec upsert_participant(String.t(), map()) :: {:ok, RoomSnapshot.t()} | {:error, term()}
  def upsert_participant(room_id, attrs) when is_binary(room_id) and is_map(attrs) do
    with {:ok, server} <- fetch_room_server(room_id),
         do: RoomServer.register_participant(server, attrs)
  end

  @spec remove_participant(String.t(), String.t()) :: {:ok, RoomSnapshot.t()} | {:error, term()}
  def remove_participant(room_id, participant_id)
      when is_binary(room_id) and is_binary(participant_id) do
    with {:ok, server} <- fetch_room_server(room_id),
         do: RoomServer.remove_participant(server, participant_id)
  end

  @spec submit_contribution(String.t(), map()) :: {:ok, RoomSnapshot.t()} | {:error, term()}
  def submit_contribution(room_id, attrs) when is_binary(room_id) and is_map(attrs) do
    with {:ok, server} <- fetch_room_server(room_id),
         do: RoomServer.submit_contribution(server, attrs)
  end

  @spec list_assignments(String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def list_assignments(room_id, opts \\ []) when is_binary(room_id) and is_list(opts) do
    with {:ok, snapshot} <- fetch_room_snapshot(room_id) do
      assignments =
        snapshot.assignments
        |> Enum.filter(fn assignment ->
          participant_match?(assignment.participant_id, Keyword.get(opts, :participant_id)) and
            status_match?(assignment.status, Keyword.get(opts, :status))
        end)
        |> maybe_limit(Keyword.get(opts, :limit))

      {:ok, assignments}
    end
  end

  @spec update_assignment(String.t(), String.t(), String.t()) ::
          {:ok, RoomSnapshot.t()} | {:error, term()}
  def update_assignment(room_id, assignment_id, status)
      when is_binary(room_id) and is_binary(assignment_id) and is_binary(status) do
    with {:ok, server} <- fetch_room_server(room_id),
         do: RoomServer.update_assignment(server, assignment_id, status)
  end

  @spec list_events(String.t(), keyword()) :: {:ok, [RoomEvent.t()]} | {:error, term()}
  def list_events(room_id, opts \\ []) when is_binary(room_id) and is_list(opts) do
    Persistence.list_room_events(room_id, opts)
  end

  @spec list_contributions(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_contributions(room_id, opts \\ []) when is_binary(room_id) and is_list(opts) do
    Persistence.list_contributions(room_id, opts)
  end

  defp initial_room_requests(room, participants, room_patch) do
    room_request = {:room_created, %{"room" => room_map(room)}}

    participant_requests =
      Enum.map(participants, fn participant ->
        {:participant_joined, %{"participant" => Participant.to_map(participant)}}
      end)

    [room_request] ++ participant_requests ++ materialize_room_patch_requests(room, room_patch)
  end

  defp apply_initial_requests(snapshot, policy_module, requests) do
    Enum.reduce_while(requests, {:ok, snapshot, []}, fn {type, data},
                                                        {:ok, current_snapshot, acc_events} ->
      case build_event(current_snapshot, type, data) do
        {:ok, event} ->
          next_snapshot = EventReducer.apply_event(current_snapshot, event)

          {:ok, policy_state, room_patch} =
            policy_module.handle_event(
              event,
              next_snapshot,
              next_snapshot.dispatch.policy_state,
              %{
                availability: %{},
                policy_state: next_snapshot.dispatch.policy_state,
                now: DateTime.utc_now()
              }
            )

          continue_initial_request(
            next_snapshot,
            policy_module,
            event,
            acc_events,
            policy_state,
            room_patch
          )

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp continue_initial_request(
         next_snapshot,
         policy_module,
         event,
         acc_events,
         policy_state,
         room_patch
       ) do
    next_snapshot = put_in(next_snapshot.dispatch.policy_state, policy_state)
    patch_requests = materialize_room_patch_requests(next_snapshot.room, room_patch)

    case apply_initial_requests(next_snapshot, policy_module, patch_requests) do
      {:ok, final_snapshot, patch_events} ->
        {:cont, {:ok, final_snapshot, acc_events ++ [event] ++ patch_events}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp build_participants(room_id, participants) do
    participants
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, acc} ->
      normalized =
        attrs
        |> map_value("meta")
        |> then(fn _meta ->
          attrs
          |> Map.put("room_id", room_id)
          |> Map.put_new("kind", string_value(attrs, "kind") || "human")
          |> Map.put_new("joined_at", DateTime.utc_now())
        end)

      case Participant.new(normalized) do
        {:ok, participant} -> {:cont, {:ok, acc ++ [participant]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp materialize_room_patch_requests(_room, room_patch) when room_patch in [%{}, nil], do: []

  defp materialize_room_patch_requests(room, room_patch) do
    []
    |> maybe_patch_phase(room, room_patch)
    |> maybe_patch_status(room, room_patch)
  end

  defp maybe_patch_phase(requests, room, room_patch) do
    if Map.has_key?(room_patch, :phase) and Map.get(room_patch, :phase) != room.phase do
      requests ++
        [
          {:room_phase_changed,
           %{"phase" => Map.get(room_patch, :phase), "inserted_at" => DateTime.utc_now()}}
        ]
    else
      requests
    end
  end

  defp maybe_patch_status(requests, room, room_patch) do
    if Map.has_key?(room_patch, :status) and Map.get(room_patch, :status) != room.status do
      requests ++
        [
          {:room_status_changed,
           %{"status" => Map.get(room_patch, :status), "inserted_at" => DateTime.utc_now()}}
        ]
    else
      requests
    end
  end

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

  defp build_event(snapshot, type, data) do
    RoomEvent.new(%{
      "id" => "evt-#{snapshot.room.id}-#{snapshot.clocks.next_event_sequence}",
      "room_id" => snapshot.room.id,
      "sequence" => snapshot.clocks.next_event_sequence,
      "type" => type,
      "data" => data,
      "inserted_at" => DateTime.utc_now()
    })
  end

  defp finalize_checkpoint(snapshot, events) do
    checkpoint =
      case List.last(events) do
        %RoomEvent{sequence: sequence} -> sequence
        _other -> snapshot.replay.checkpoint_event_sequence
      end

    put_in(snapshot.replay.checkpoint_event_sequence, checkpoint)
  end

  defp fetch_room_server(room_id) do
    with {:ok, _snapshot} <- fetch_room_snapshot(room_id),
         [{pid, _value}] <- Registry.lookup(JidoHiveServer.Collaboration.Registry, room_id) do
      {:ok, pid}
    else
      [] -> {:error, :room_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_room_server(%RoomSnapshot{} = snapshot) do
    case Registry.lookup(JidoHiveServer.Collaboration.Registry, snapshot.room.id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        spec = {RoomServer, room_id: snapshot.room.id, snapshot: snapshot}

        case DynamicSupervisor.start_child(JidoHiveServer.Collaboration.RoomSupervisor, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp replace_room_server(room_id) do
    case Registry.lookup(JidoHiveServer.Collaboration.Registry, room_id) do
      [{pid, _value}] ->
        GenServer.stop(pid, :normal)
        :ok

      [] ->
        :ok
    end
  end

  defp participant_match?(_assignment_value, nil), do: true
  defp participant_match?(assignment_value, expected), do: assignment_value == expected

  defp status_match?(_assignment_value, nil), do: true
  defp status_match?(assignment_value, expected), do: assignment_value == expected

  defp maybe_limit(list, nil), do: list
  defp maybe_limit(list, limit) when is_integer(limit) and limit > 0, do: Enum.take(list, limit)
  defp maybe_limit(list, _limit), do: list

  defp generated_room_id do
    "room-#{System.unique_integer([:positive])}"
  end

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp string_value(map, key) do
    case value(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _other ->
        nil
    end
  end

  defp map_value(map, key) do
    case value(map, key) do
      %{} = nested -> nested
      _other -> %{}
    end
  end

  defp list_value(map, key) do
    case value(map, key) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp existing_atom_key(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
