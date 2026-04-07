defmodule JidoHiveServer.Collaboration.EventReducer do
  @moduledoc false

  alias JidoHiveServer.Collaboration.DispatchPolicy.Registry, as: PolicyRegistry
  alias JidoHiveServer.Collaboration.Schema.{Assignment, ContextObject, Contribution, RoomEvent}
  alias JidoHiveServer.Collaboration.SnapshotProjection

  @max_tracked_event_ids 256

  @spec apply_event(map(), RoomEvent.t()) :: map()
  def apply_event(snapshot, %RoomEvent{} = event) when is_map(snapshot) do
    if applied_event?(snapshot, event.event_id) do
      snapshot
    else
      snapshot
      |> reduce_event(event)
      |> SnapshotProjection.project()
      |> remember_event_id(event.event_id)
    end
  end

  @spec reduce(map(), [RoomEvent.t()]) :: map()
  def reduce(snapshot, events) when is_map(snapshot) and is_list(events) do
    Enum.reduce(events, snapshot, &apply_event(&2, &1))
  end

  defp reduce_event(snapshot, %RoomEvent{type: :room_created, payload: payload}) do
    Map.merge(snapshot, payload)
  end

  defp reduce_event(snapshot, %RoomEvent{type: :assignment_opened, payload: payload}) do
    assignment_payload = map_value(payload, "assignment")

    case Assignment.new(assignment_payload) do
      {:ok, assignment} ->
        assignment_map = Map.from_struct(assignment)

        %{
          snapshot
          | current_assignment: assignment_map,
            assignments: snapshot.assignments ++ [assignment_map],
            next_assignment_seq: snapshot.next_assignment_seq + 1,
            status: "running"
        }

      {:error, _reason} ->
        snapshot
    end
  end

  defp reduce_event(snapshot, %RoomEvent{} = event) when event.type == :contribution_recorded do
    contribution_payload =
      event.payload
      |> map_value("contribution")
      |> Map.put_new("contribution_id", "contrib-#{snapshot.next_contribution_seq}")

    case Contribution.new(contribution_payload) do
      {:ok, contribution} ->
        contribution_map = Map.from_struct(contribution)

        {context_objects, next_context_seq} =
          materialize_context_objects(snapshot, contribution_map, event)

        assignments = complete_assignment(snapshot.assignments, contribution_map)

        updated =
          snapshot
          |> Map.put(
            :current_assignment,
            clear_current_assignment(snapshot.current_assignment, contribution_map.assignment_id)
          )
          |> Map.put(:assignments, assignments)
          |> Map.put(:contributions, snapshot.contributions ++ [contribution_map])
          |> Map.put(:context_objects, snapshot.context_objects ++ context_objects)
          |> Map.put(:next_context_seq, next_context_seq)
          |> Map.put(:next_contribution_seq, snapshot.next_contribution_seq + 1)
          |> increment_completed_slots(contribution_map.assignment_id)

        %{updated | status: policy_status(updated)}

      {:error, _reason} ->
        snapshot
    end
  end

  defp reduce_event(snapshot, %RoomEvent{type: :assignment_abandoned, payload: payload}) do
    assignment_id = value(payload, "assignment_id")
    reason = value(payload, "reason")

    updated =
      snapshot
      |> Map.put(
        :current_assignment,
        clear_current_assignment(snapshot.current_assignment, assignment_id)
      )
      |> Map.put(:assignments, abandon_assignment(snapshot.assignments, assignment_id, reason))
      |> increment_completed_slots(assignment_id)

    %{updated | status: policy_status(updated)}
  end

  defp reduce_event(snapshot, %RoomEvent{type: :runtime_state_changed, payload: payload}) do
    %{snapshot | status: value(payload, "status") || snapshot.status}
  end

  defp reduce_event(snapshot, _event), do: snapshot

  defp materialize_context_objects(snapshot, contribution, event) do
    drafts = Map.get(contribution, :context_objects, [])

    Enum.map_reduce(drafts, snapshot.next_context_seq, fn draft, seq ->
      attrs = %{
        context_id: "ctx-#{seq}",
        authored_by: %{
          participant_id: contribution.participant_id,
          participant_role: contribution.participant_role,
          target_id: contribution.target_id,
          capability_id: contribution.capability_id
        },
        provenance: %{
          contribution_id: contribution.contribution_id,
          assignment_id: contribution.assignment_id,
          consumed_context_ids: contribution.consumed_context_ids,
          source_event_ids: [event.event_id],
          authority_level: contribution.authority_level,
          contribution_type: contribution.contribution_type
        },
        inserted_at: event.recorded_at
      }

      context_object =
        case ContextObject.from_draft(draft, attrs) do
          {:ok, context_object} -> Map.from_struct(context_object)
          {:error, _reason} -> nil
        end

      {context_object, seq + 1}
    end)
    |> then(fn {context_objects, next_seq} ->
      {Enum.reject(context_objects, &is_nil/1), next_seq}
    end)
  end

  defp complete_assignment(assignments, contribution) do
    Enum.map(assignments, fn assignment ->
      if assignment.assignment_id == contribution.assignment_id do
        assignment
        |> Map.put(:status, contribution.status || "completed")
        |> Map.put(:completed_at, DateTime.utc_now())
        |> Map.put(:result_summary, contribution.summary)
      else
        assignment
      end
    end)
  end

  defp abandon_assignment(assignments, assignment_id, reason) do
    Enum.map(assignments, fn assignment ->
      if assignment.assignment_id == assignment_id do
        assignment
        |> Map.put(:status, "abandoned")
        |> Map.put(:completed_at, DateTime.utc_now())
        |> Map.put(:result_summary, reason)
      else
        assignment
      end
    end)
  end

  defp clear_current_assignment(current_assignment, assignment_id) do
    if current_assignment == %{} or current_assignment.assignment_id != assignment_id do
      current_assignment
    else
      %{}
    end
  end

  defp increment_completed_slots(snapshot, nil), do: snapshot

  defp increment_completed_slots(snapshot, assignment_id) do
    if Enum.any?(snapshot.assignments, &(&1.assignment_id == assignment_id)) do
      update_in(snapshot, [:dispatch_state, :completed_slots], fn value -> (value || 0) + 1 end)
    else
      snapshot
    end
  end

  defp policy_status(snapshot) do
    case PolicyRegistry.fetch_module(snapshot.dispatch_policy_id) do
      {:ok, module} -> module.status(snapshot)
      {:error, _reason} -> snapshot.status || "idle"
    end
  end

  defp applied_event?(snapshot, event_id) when is_binary(event_id) do
    snapshot
    |> Map.get(:dispatch_state, %{})
    |> Map.get(:applied_event_ids, [])
    |> Enum.member?(event_id)
  end

  defp applied_event?(_snapshot, _event_id), do: false

  defp remember_event_id(snapshot, nil), do: snapshot

  defp remember_event_id(snapshot, event_id) do
    ids =
      snapshot
      |> Map.get(:dispatch_state, %{})
      |> Map.get(:applied_event_ids, [])
      |> Kernel.++([event_id])
      |> Enum.uniq()
      |> Enum.take(-@max_tracked_event_ids)

    put_in(snapshot, [:dispatch_state, :applied_event_ids], ids)
  end

  defp map_value(map, key) do
    case value(map, key) do
      %{} = value -> value
      _other -> %{}
    end
  end

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
