defmodule JidoHiveServer.Collaboration.EventReducer do
  @moduledoc false

  alias JidoHiveServer.Collaboration.DispatchPolicy.Registry, as: PolicyRegistry
  alias JidoHiveServer.Collaboration.Schema.{Assignment, Contribution, RoomEvent}
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

  defp reduce_event(snapshot, %RoomEvent{type: :room_status_changed, payload: payload}) do
    %{snapshot | status: value(payload, "status") || snapshot.status}
  end

  defp reduce_event(snapshot, %RoomEvent{type: :room_phase_changed, payload: payload}) do
    Map.put(snapshot, :phase, value(payload, "phase"))
  end

  defp reduce_event(snapshot, %RoomEvent{type: :participant_joined, payload: payload}) do
    participant = map_value(payload, "participant")
    participant_id = value(participant, "participant_id") || value(participant, "id")

    participants =
      snapshot
      |> Map.get(:participants, [])
      |> Enum.reject(fn existing ->
        value(existing, "participant_id") == participant_id or
          value(existing, "id") == participant_id
      end)
      |> Kernel.++([participant])

    Map.put(snapshot, :participants, participants)
  end

  defp reduce_event(snapshot, %RoomEvent{type: :participant_left, payload: payload}) do
    participant_id = value(payload, "participant_id") || value(payload, "id")

    participants =
      snapshot
      |> Map.get(:participants, [])
      |> Enum.reject(fn existing ->
        value(existing, "participant_id") == participant_id or
          value(existing, "id") == participant_id
      end)

    Map.put(snapshot, :participants, participants)
  end

  defp reduce_event(snapshot, %RoomEvent{type: :assignment_created, payload: payload}) do
    assignment_payload = map_value(payload, "assignment")

    assignment_payload =
      if assignment_payload == %{}, do: payload, else: assignment_payload

    case Assignment.new(assignment_payload) do
      {:ok, assignment} ->
        assignment_map = Map.from_struct(assignment)

        %{
          snapshot
          | current_assignment: assignment_map,
            assignments: upsert_assignment(snapshot.assignments, assignment_map),
            next_assignment_seq: snapshot.next_assignment_seq + 1,
            status: "running"
        }

      {:error, _reason} ->
        snapshot
    end
  end

  defp reduce_event(snapshot, %RoomEvent{type: :assignment_opened, payload: payload}) do
    reduce_event(snapshot, %RoomEvent{type: :assignment_created, payload: payload})
  end

  defp reduce_event(snapshot, %RoomEvent{type: :contribution_submitted, payload: payload}) do
    contribution_payload =
      payload
      |> map_value("contribution")
      |> case do
        %{} = nested when map_size(nested) > 0 ->
          nested

        _other ->
          payload
      end
      |> Map.put_new("contribution_id", "contrib-#{snapshot.next_contribution_seq}")

    case Contribution.new(contribution_payload) do
      {:ok, contribution} ->
        contribution_map = Map.from_struct(contribution)

        snapshot
        |> Map.put(:contributions, snapshot.contributions ++ [contribution_map])
        |> Map.put(:next_contribution_seq, snapshot.next_contribution_seq + 1)

      {:error, _reason} ->
        snapshot
    end
  end

  defp reduce_event(snapshot, %RoomEvent{type: :contribution_recorded, payload: payload}) do
    contribution_payload =
      payload
      |> map_value("contribution")
      |> case do
        %{} = nested when map_size(nested) > 0 ->
          nested

        _other ->
          payload
      end
      |> Map.put_new("contribution_id", "contrib-#{snapshot.next_contribution_seq}")

    case Contribution.new(contribution_payload) do
      {:ok, contribution} ->
        contribution_map = Map.from_struct(contribution)
        assignment_id = contribution.assignment_id

        updated =
          snapshot
          |> Map.put(:contributions, snapshot.contributions ++ [contribution_map])
          |> Map.put(:next_contribution_seq, snapshot.next_contribution_seq + 1)

        if is_binary(assignment_id) and assignment_id != "" do
          updated =
            updated
            |> Map.put(
              :current_assignment,
              clear_current_assignment(snapshot.current_assignment, assignment_id)
            )
            |> Map.put(
              :assignments,
              update_assignment_status(
                snapshot.assignments,
                assignment_id,
                contribution.status,
                contribution.summary
              )
            )
            |> increment_completed_slots(assignment_id)

          %{updated | status: policy_status(updated)}
        else
          updated
        end

      {:error, _reason} ->
        snapshot
    end
  end

  defp reduce_event(snapshot, %RoomEvent{type: :assignment_completed, payload: payload}) do
    assignment_id = value(payload, "assignment_id")
    result_summary = value(payload, "result_summary")
    status = value(payload, "status") || "completed"

    updated =
      snapshot
      |> Map.put(
        :current_assignment,
        clear_current_assignment(snapshot.current_assignment, assignment_id)
      )
      |> Map.put(
        :assignments,
        update_assignment_status(snapshot.assignments, assignment_id, status, result_summary)
      )
      |> increment_completed_slots(assignment_id)

    %{updated | status: policy_status(updated)}
  end

  defp reduce_event(snapshot, %RoomEvent{type: :assignment_expired, payload: payload}) do
    assignment_id = value(payload, "assignment_id")
    reason = value(payload, "reason")

    updated =
      snapshot
      |> Map.put(
        :current_assignment,
        clear_current_assignment(snapshot.current_assignment, assignment_id)
      )
      |> Map.put(
        :assignments,
        update_assignment_status(snapshot.assignments, assignment_id, "expired", reason)
      )
      |> increment_completed_slots(assignment_id)

    %{updated | status: policy_status(updated)}
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
      |> Map.put(
        :assignments,
        update_assignment_status(snapshot.assignments, assignment_id, "abandoned", reason)
      )
      |> increment_completed_slots(assignment_id)

    %{updated | status: policy_status(updated)}
  end

  defp reduce_event(snapshot, _event), do: snapshot

  defp upsert_assignment(assignments, assignment) do
    assignment_id = Map.get(assignment, :assignment_id)

    assignments
    |> Enum.reject(&(Map.get(&1, :assignment_id) == assignment_id))
    |> Kernel.++([assignment])
  end

  defp update_assignment_status(assignments, assignment_id, status, result_summary) do
    Enum.map(assignments, fn assignment ->
      if assignment.assignment_id == assignment_id do
        assignment
        |> Map.put(:status, status)
        |> Map.put(:completed_at, DateTime.utc_now())
        |> Map.put(:result_summary, result_summary)
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
