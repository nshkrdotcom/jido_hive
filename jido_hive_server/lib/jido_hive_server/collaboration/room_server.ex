defmodule JidoHiveServer.Collaboration.RoomServer do
  @moduledoc false

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoHiveServer.Collaboration.{EventReducer, SnapshotProjection}
  alias JidoHiveServer.Collaboration.Schema.RoomEvent
  alias JidoHiveServer.Persistence
  alias Phoenix.PubSub

  def start_link(opts) when is_list(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, opts, name: via(room_id))
  end

  def open_assignment(server, payload) when is_map(payload) do
    GenServer.call(server, {:open_assignment, payload})
  end

  def record_contribution(server, payload) when is_map(payload) do
    GenServer.call(server, {:record_contribution, payload})
  end

  def abandon_assignment(server, payload) when is_map(payload) do
    GenServer.call(server, {:abandon_assignment, payload})
  end

  def set_runtime_state(server, payload) when is_map(payload) do
    GenServer.call(server, {:set_runtime_state, payload})
  end

  def snapshot(server) do
    GenServer.call(server, :snapshot)
  end

  def via(room_id) do
    {:via, Registry, {JidoHiveServer.Collaboration.Registry, room_id}}
  end

  @impl true
  def init(opts) do
    initial_snapshot = Keyword.fetch!(opts, :snapshot)
    {:ok, %{snapshot: SnapshotProjection.project(initial_snapshot)}}
  end

  @impl true
  def handle_call({:open_assignment, payload}, _from, %{snapshot: snapshot} = state) do
    case do_apply_single_event(snapshot, :assignment_created, payload) do
      {:ok, next_snapshot, _event} ->
        publish_signal("room.assignment.created", next_snapshot)
        {:reply, {:ok, next_snapshot}, %{state | snapshot: next_snapshot}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:record_contribution, payload}, _from, %{snapshot: snapshot} = state) do
    case do_record_contribution(snapshot, payload) do
      {:ok, final_snapshot} ->
        publish_signal("room.contribution.submitted", final_snapshot)
        {:reply, {:ok, final_snapshot}, %{state | snapshot: final_snapshot}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:abandon_assignment, payload}, _from, %{snapshot: snapshot} = state) do
    case do_apply_single_event(snapshot, :assignment_expired, payload) do
      {:ok, next_snapshot, _event} ->
        publish_signal("room.assignment.expired", next_snapshot)
        {:reply, {:ok, next_snapshot}, %{state | snapshot: next_snapshot}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_runtime_state, payload}, _from, %{snapshot: snapshot} = state) do
    case do_apply_single_event(snapshot, :room_status_changed, payload) do
      {:ok, next_snapshot, _event} ->
        publish_signal("room.runtime.updated", next_snapshot)
        {:reply, {:ok, next_snapshot}, %{state | snapshot: next_snapshot}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:snapshot, _from, %{snapshot: snapshot} = state) do
    {:reply, {:ok, snapshot}, state}
  end

  defp room_event(room_id, type, payload)
       when is_binary(room_id) and is_atom(type) and is_map(payload) do
    RoomEvent.new(%{
      event_id: unique_id("evt"),
      room_id: room_id,
      type: type,
      payload: payload,
      recorded_at: DateTime.utc_now()
    })
  end

  defp publish_signal(type, data) do
    signal = Signal.new!(type, data, source: "/jido_hive_server/room_server")
    _ = Bus.publish(JidoHiveServer.SignalBus, [signal])
    room_id = Map.get(data, :room_id) || Map.get(data, "room_id")

    if is_binary(room_id) and room_id != "" do
      PubSub.broadcast(JidoHiveServer.PubSub, "room:#{room_id}", {:room_event, type, data})
    end

    :ok
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp do_apply_single_event(snapshot, type, payload) do
    with {:ok, event} <- room_event(snapshot.room_id, type, payload),
         next_snapshot <- EventReducer.apply_event(snapshot, event),
         {:ok, _snapshot} <- Persistence.persist_room_transition(next_snapshot, [event]) do
      {:ok, next_snapshot, event}
    end
  end

  defp do_record_contribution(snapshot, payload) do
    with :ok <- validate_contribution(snapshot, payload) do
      case contribution_recording_decision(snapshot, payload) do
        :record ->
          record_new_contribution(snapshot, payload)

        :idempotent ->
          {:ok, snapshot}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp record_new_contribution(snapshot, payload) do
    with {:ok, events} <- contribution_events(snapshot.room_id, payload),
         final_snapshot <- EventReducer.reduce(snapshot, events),
         {:ok, _snapshot} <- Persistence.persist_room_transition(final_snapshot, events) do
      {:ok, final_snapshot}
    end
  end

  defp contribution_events(room_id, payload) do
    contribution = map_value(payload, "contribution")
    assignment_id = value(contribution, "assignment_id")

    with {:ok, contribution_event} <- room_event(room_id, :contribution_submitted, payload),
         {:ok, completion_event} <-
           maybe_assignment_completion_event(room_id, assignment_id, contribution) do
      {:ok, Enum.reject([contribution_event, completion_event], &is_nil/1)}
    end
  end

  defp maybe_assignment_completion_event(_room_id, assignment_id, _contribution)
       when not is_binary(assignment_id) or assignment_id == "",
       do: {:ok, nil}

  defp maybe_assignment_completion_event(room_id, assignment_id, contribution) do
    room_event(room_id, :assignment_completed, %{
      "assignment_id" => assignment_id,
      "result_summary" => value(contribution, "summary"),
      "status" => value(contribution, "status") || "completed"
    })
  end

  defp contribution_recording_decision(snapshot, payload) do
    contribution = map_value(payload, "contribution")
    contribution_id = value(contribution, "contribution_id")
    assignment_id = value(contribution, "assignment_id")
    participant_id = value(contribution, "participant_id")

    Enum.reduce_while(snapshot.contributions, :record, fn existing, _decision ->
      cond do
        duplicate_contribution_id?(existing, contribution_id) and
            duplicate_assignment_result?(existing, assignment_id, participant_id) ->
          {:halt, :idempotent}

        duplicate_contribution_id?(existing, contribution_id) ->
          {:halt,
           {:error,
            {:duplicate_contribution_id_conflict,
             %{
               contribution_id: contribution_id,
               existing_assignment_id: value(existing, "assignment_id"),
               incoming_assignment_id: assignment_id,
               existing_participant_id: value(existing, "participant_id"),
               incoming_participant_id: participant_id
             }}}}

        duplicate_assignment_result?(existing, assignment_id, participant_id) ->
          {:halt,
           {:error,
            {:duplicate_assignment_result_conflict,
             %{
               assignment_id: assignment_id,
               participant_id: participant_id,
               existing_contribution_id: value(existing, "contribution_id"),
               incoming_contribution_id: contribution_id
             }}}}

        true ->
          {:cont, :record}
      end
    end)
  end

  defp duplicate_contribution_id?(_existing, nil), do: false

  defp duplicate_contribution_id?(existing, contribution_id) do
    value(existing, "contribution_id") == contribution_id
  end

  defp duplicate_assignment_result?(_existing, assignment_id, participant_id)
       when not is_binary(assignment_id) or not is_binary(participant_id),
       do: false

  defp duplicate_assignment_result?(existing, assignment_id, participant_id) do
    value(existing, "assignment_id") == assignment_id and
      value(existing, "participant_id") == participant_id
  end

  defp validate_contribution(snapshot, payload) do
    contribution = map_value(payload, "contribution")

    case contribution_validator(snapshot) do
      nil ->
        :ok

      validator ->
        validator.validate(contribution, snapshot)
    end
  end

  defp contribution_validator(snapshot) do
    config = Map.get(snapshot, :config) || Map.get(snapshot, "config") || %{}

    case resolve_validator_module(
           Map.get(config, "contribution_validator") || Map.get(config, :contribution_validator)
         ) do
      nil ->
        if legacy_context_graph_room?(snapshot) do
          JidoHiveContextGraph.ContributionValidator
        end

      module ->
        module
    end
  end

  defp legacy_context_graph_room?(snapshot) do
    Map.has_key?(snapshot, :context_config) or Map.has_key?(snapshot, "context_config")
  end

  defp resolve_validator_module(module) when is_atom(module), do: module

  defp resolve_validator_module(module) when is_binary(module) do
    String.to_existing_atom(module)
  rescue
    ArgumentError -> nil
  end

  defp resolve_validator_module(_module), do: nil

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp map_value(map, key) do
    case value(map, key) do
      %{} = nested -> nested
      _other -> %{}
    end
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
