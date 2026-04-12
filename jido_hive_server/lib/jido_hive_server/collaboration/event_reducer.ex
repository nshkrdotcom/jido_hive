defmodule JidoHiveServer.Collaboration.EventReducer do
  @moduledoc false

  alias JidoHiveServer.Collaboration.Schema.{
    Assignment,
    Contribution,
    Participant,
    Room,
    RoomEvent,
    RoomSnapshot
  }

  @spec apply_event(RoomSnapshot.t(), RoomEvent.t()) :: RoomSnapshot.t()
  def apply_event(%RoomSnapshot{} = snapshot, %RoomEvent{} = event) do
    snapshot
    |> reduce_event(event)
    |> advance_event_clock(event)
  end

  @spec reduce(RoomSnapshot.t(), [RoomEvent.t()]) :: RoomSnapshot.t()
  def reduce(%RoomSnapshot{} = snapshot, events) when is_list(events) do
    Enum.reduce(events, snapshot, &apply_event(&2, &1))
  end

  defp reduce_event(snapshot, %RoomEvent{type: :room_created, data: data}) do
    case Room.new(data["room"] || data[:room] || data) do
      {:ok, room} -> %{snapshot | room: room}
      {:error, _reason} -> snapshot
    end
  end

  defp reduce_event(snapshot, %RoomEvent{type: :room_status_changed, data: data}) do
    %{
      snapshot
      | room: %{
          snapshot.room
          | status: value(data, "status") || snapshot.room.status,
            updated_at: timestamp(data, snapshot.room.updated_at)
        }
    }
  end

  defp reduce_event(snapshot, %RoomEvent{type: :room_phase_changed, data: data}) do
    %{
      snapshot
      | room: %{
          snapshot.room
          | phase: phase_value(data),
            updated_at: timestamp(data, snapshot.room.updated_at)
        }
    }
  end

  defp reduce_event(snapshot, %RoomEvent{type: :participant_joined, data: data}) do
    participant_data = data["participant"] || data[:participant] || data

    case Participant.new(participant_data) do
      {:ok, participant} ->
        participants =
          snapshot.participants
          |> Enum.reject(&(&1.id == participant.id))
          |> Kernel.++([participant])

        %{snapshot | participants: participants}

      {:error, _reason} ->
        snapshot
    end
  end

  defp reduce_event(snapshot, %RoomEvent{type: :participant_left, data: data}) do
    participant_id = value(data, "participant_id") || value(data, "id")

    participants =
      Enum.reject(snapshot.participants, &(&1.id == participant_id))

    %{snapshot | participants: participants}
  end

  defp reduce_event(snapshot, %RoomEvent{type: :assignment_created, data: data}) do
    assignment_data = data["assignment"] || data[:assignment] || data

    case Assignment.new(assignment_data) do
      {:ok, assignment} ->
        existing? = Enum.any?(snapshot.assignments, &(&1.id == assignment.id))

        assignments =
          snapshot.assignments
          |> Enum.reject(&(&1.id == assignment.id))
          |> Kernel.++([assignment])

        dispatch =
          snapshot.dispatch
          |> Map.update!(:active_assignment_ids, &Enum.uniq(&1 ++ [assignment.id]))
          |> Map.update!(
            :completed_assignment_ids,
            &Enum.reject(&1, fn id -> id == assignment.id end)
          )

        clocks =
          if existing? do
            snapshot.clocks
          else
            Map.update!(snapshot.clocks, :next_assignment_seq, &(&1 + 1))
          end

        %{snapshot | assignments: assignments, dispatch: dispatch, clocks: clocks}

      {:error, _reason} ->
        snapshot
    end
  end

  defp reduce_event(snapshot, %RoomEvent{type: :assignment_completed, data: data}) do
    assignment_id = value(data, "assignment_id")
    update_assignment_terminal(snapshot, assignment_id, "completed")
  end

  defp reduce_event(snapshot, %RoomEvent{type: :assignment_expired, data: data}) do
    assignment_id = value(data, "assignment_id")
    update_assignment_terminal(snapshot, assignment_id, "expired")
  end

  defp reduce_event(snapshot, %RoomEvent{type: :contribution_submitted, data: data}) do
    contribution_data = data["contribution"] || data[:contribution] || data

    case Contribution.new(contribution_data) do
      {:ok, contribution} ->
        clocks = Map.update!(snapshot.clocks, :next_contribution_seq, &(&1 + 1))
        %{snapshot | contributions: snapshot.contributions ++ [contribution], clocks: clocks}

      {:error, _reason} ->
        snapshot
    end
  end

  defp reduce_event(snapshot, _event), do: snapshot

  defp update_assignment_terminal(%RoomSnapshot{} = snapshot, assignment_id, status) do
    assignments =
      Enum.map(snapshot.assignments, fn assignment ->
        if assignment.id == assignment_id do
          %{assignment | status: status}
        else
          assignment
        end
      end)

    dispatch =
      snapshot.dispatch
      |> Map.update!(:active_assignment_ids, &Enum.reject(&1, fn id -> id == assignment_id end))
      |> maybe_track_completed_assignment(status, assignment_id)

    %{snapshot | assignments: assignments, dispatch: dispatch}
  end

  defp maybe_track_completed_assignment(dispatch, "completed", assignment_id) do
    Map.update!(dispatch, :completed_assignment_ids, &Enum.uniq(&1 ++ [assignment_id]))
  end

  defp maybe_track_completed_assignment(dispatch, _status, _assignment_id), do: dispatch

  defp advance_event_clock(%RoomSnapshot{} = snapshot, %RoomEvent{sequence: sequence}) do
    put_in(
      snapshot.clocks.next_event_sequence,
      max(snapshot.clocks.next_event_sequence, sequence + 1)
    )
  end

  defp phase_value(data) do
    case value(data, "phase") do
      value when is_binary(value) -> value
      nil -> nil
      _other -> nil
    end
  end

  defp timestamp(data, default) do
    case value(data, "inserted_at") do
      %DateTime{} = value ->
        value

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> datetime
          _other -> default
        end

      _other ->
        default
    end
  end

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
