defmodule JidoHiveServer.Collaboration.RoomServer do
  @moduledoc false

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoHiveServer.Collaboration.{ContextManager, EventReducer, SnapshotProjection}
  alias JidoHiveServer.Collaboration.Schema.RoomEvent
  alias JidoHiveServer.Persistence

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
    case do_apply_single_event(snapshot, :assignment_opened, payload) do
      {:ok, next_snapshot, _event} ->
        publish_signal("room.assignment.opened", next_snapshot)
        {:reply, {:ok, next_snapshot}, %{state | snapshot: next_snapshot}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:record_contribution, payload}, _from, %{snapshot: snapshot} = state) do
    participant = contribution_participant(snapshot, payload)
    write_intent = contribution_write_intent(payload)

    case do_record_contribution(snapshot, payload, participant, write_intent) do
      {:ok, final_snapshot} ->
        publish_signal("room.contribution.recorded", final_snapshot)
        {:reply, {:ok, final_snapshot}, %{state | snapshot: final_snapshot}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:abandon_assignment, payload}, _from, %{snapshot: snapshot} = state) do
    case do_apply_single_event(snapshot, :assignment_abandoned, payload) do
      {:ok, next_snapshot, _event} ->
        publish_signal("room.assignment.abandoned", next_snapshot)
        {:reply, {:ok, next_snapshot}, %{state | snapshot: next_snapshot}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_runtime_state, payload}, _from, %{snapshot: snapshot} = state) do
    case do_apply_single_event(snapshot, :runtime_state_changed, payload) do
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

  defp do_record_contribution(snapshot, payload, participant, write_intent) do
    if duplicate_contribution?(snapshot, payload) do
      {:ok, snapshot}
    else
      with :ok <- ContextManager.validate_append(participant, write_intent, snapshot),
           {:ok, event} <- room_event(snapshot.room_id, :contribution_recorded, payload),
           base_snapshot <- EventReducer.apply_event(snapshot, event),
           appended_context_ids <- appended_context_ids(snapshot, base_snapshot),
           %{room_events: derived_event_attrs} <-
             ContextManager.after_append(snapshot, base_snapshot, appended_context_ids),
           {:ok, derived_events} <-
             room_events_from_attrs(snapshot.room_id, event, derived_event_attrs),
           final_snapshot <- EventReducer.reduce(base_snapshot, derived_events),
           {:ok, _snapshot} <-
             Persistence.persist_room_transition(final_snapshot, [event | derived_events]) do
        {:ok, final_snapshot}
      end
    end
  end

  defp contribution_participant(snapshot, payload) do
    contribution = map_value(payload, "contribution")
    participant_id = value(contribution, "participant_id")

    Enum.find(snapshot.participants, &(&1.participant_id == participant_id)) ||
      %{
        participant_id: participant_id,
        participant_role: value(contribution, "participant_role"),
        participant_kind: value(contribution, "participant_kind") || "human",
        authority_level: value(contribution, "authority_level"),
        target_id: value(contribution, "target_id"),
        capability_id: value(contribution, "capability_id")
      }
  end

  defp contribution_write_intent(payload) do
    context_objects =
      payload
      |> map_value("contribution")
      |> list_value("context_objects")

    %{
      drafted_object_types:
        Enum.map(context_objects, fn context_object -> value(context_object, "object_type") end)
        |> Enum.reject(&is_nil/1),
      relation_targets_by_type:
        Enum.reduce(context_objects, %{}, fn context_object, acc ->
          context_object
          |> list_value("relations")
          |> Enum.reduce(acc, fn relation, relation_acc ->
            case relation_key(relation) do
              nil ->
                relation_acc

              relation_type ->
                Map.update(
                  relation_acc,
                  relation_type,
                  [relation_target_id(relation)],
                  &(&1 ++ [relation_target_id(relation)])
                )
            end
          end)
        end),
      invalid_relations:
        Enum.flat_map(context_objects, fn context_object ->
          context_object
          |> list_value("relations")
          |> Enum.flat_map(&invalid_relation_entries/1)
        end)
    }
  end

  defp invalid_relation_entries(relation) do
    relation_name = value(relation, "relation")
    target_id = relation_target_id(relation)

    cond do
      relation_key(relation) == nil ->
        [%{kind: :invalid_relation_type, relation: relation_name}]

      relation_key(relation) != nil and not valid_relation_target_id?(target_id) ->
        [%{kind: :missing_relation_target, relation: relation_name}]

      true ->
        []
    end
  end

  defp appended_context_ids(before_snapshot, after_snapshot) do
    before_ids =
      before_snapshot.context_objects
      |> Enum.map(& &1.context_id)
      |> MapSet.new()

    after_snapshot.context_objects
    |> Enum.map(& &1.context_id)
    |> Enum.reject(&MapSet.member?(before_ids, &1))
  end

  defp room_events_from_attrs(room_id, causation_event, attrs_list) do
    attrs_list
    |> Enum.map(fn attrs ->
      room_event(room_id, attrs.type, attrs.payload)
      |> case do
        {:ok, event} ->
          {:ok,
           %{
             event
             | causation_id: causation_event.event_id,
               correlation_id: causation_event.correlation_id,
               recorded_at: causation_event.recorded_at
           }}

        {:error, _reason} = error ->
          error
      end
    end)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, event}, {:ok, acc} -> {:cont, {:ok, acc ++ [event]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
  end

  defp relation_key(relation) do
    case value(relation, "relation") do
      "derives_from" -> :derives_from
      "references" -> :references
      "contradicts" -> :contradicts
      "resolves" -> :resolves
      "supersedes" -> :supersedes
      "supports" -> :supports
      "blocks" -> :blocks
      _other -> nil
    end
  end

  defp relation_target_id(relation), do: value(relation, "target_id")

  defp valid_relation_target_id?(target_id) when is_binary(target_id),
    do: String.trim(target_id) != ""

  defp valid_relation_target_id?(_target_id), do: false

  defp duplicate_contribution?(snapshot, payload) do
    contribution = map_value(payload, "contribution")
    contribution_id = value(contribution, "contribution_id")
    assignment_id = value(contribution, "assignment_id")
    participant_id = value(contribution, "participant_id")

    Enum.any?(snapshot.contributions, fn existing ->
      duplicate_contribution_id?(existing, contribution_id) or
        duplicate_assignment_result?(existing, assignment_id, participant_id)
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

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp map_value(map, key) do
    case value(map, key) do
      %{} = nested -> nested
      _other -> %{}
    end
  end

  defp list_value(map, key) do
    case value(map, key) do
      list when is_list(list) -> list
      _other -> []
    end
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
