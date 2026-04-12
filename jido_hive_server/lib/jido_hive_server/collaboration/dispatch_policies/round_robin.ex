defmodule JidoHiveServer.Collaboration.DispatchPolicies.RoundRobin do
  @moduledoc false

  @behaviour JidoHiveServer.Collaboration.DispatchPolicy

  alias JidoHiveServer.Collaboration.Schema.{Participant, RoomSnapshot}

  @policy_id "round_robin/v2"
  @default_phase_cycle ["analysis", "critique", "synthesis"]

  @impl true
  def id, do: @policy_id

  @impl true
  def definition do
    %{
      policy_id: @policy_id,
      config: %{
        assignment_limit: "participant_count * 3 by default",
        phase_cycle: @default_phase_cycle
      }
    }
  end

  @impl true
  def init(%RoomSnapshot{} = snapshot, _context) do
    phase_cycle = phase_cycle(snapshot)

    {:ok,
     %{
       cursor: 0,
       assignment_limit: assignment_limit(snapshot),
       phase_cycle: phase_cycle
     }, phase_patch(snapshot, phase_cycle, completed_assignment_count(snapshot))}
  end

  @impl true
  def handle_event(_event, %RoomSnapshot{} = snapshot, policy_state, _context)
      when is_map(policy_state) do
    _ = snapshot
    {:ok, policy_state, %{}}
  end

  @impl true
  def select(%RoomSnapshot{} = snapshot, %{availability: availability, policy_state: policy_state}) do
    phase_cycle = phase_cycle_from_state(policy_state)
    completed_count = completed_assignment_count(snapshot)
    limit = assignment_limit_from_state(snapshot, policy_state)

    cond do
      snapshot.room.status in ["closed", "failed"] ->
        {:close, String.to_atom(snapshot.room.status), policy_state, %{}}

      snapshot.room.status == "completed" ->
        {:complete, %{reason: :already_completed}, policy_state, %{}}

      completed_count >= limit ->
        {:complete, %{reason: :assignment_limit_reached}, policy_state, %{status: "completed"}}

      active_assignment?(snapshot) ->
        {:wait, :assignment_in_progress, policy_state, %{status: "active"}}

      true ->
        select_next_participant(
          snapshot,
          availability,
          policy_state,
          phase_cycle,
          completed_count
        )
    end
  end

  defp select_next_participant(snapshot, availability, policy_state, phase_cycle, completed_count) do
    participants = agent_participants(snapshot)

    case available_rotation(participants, availability, Map.get(policy_state, :cursor, 0)) do
      [] ->
        {:wait, :no_available_participants, policy_state, %{status: "waiting"}}

      [%Participant{id: participant_id} | _rest] ->
        next_cursor = next_cursor(participants, participant_id)
        next_policy_state = Map.put(policy_state, :cursor, next_cursor)

        patch =
          %{status: "active"} |> Map.merge(phase_patch(snapshot, phase_cycle, completed_count))

        {:dispatch, [participant_id], next_policy_state, patch}
    end
  end

  defp phase_patch(snapshot, phase_cycle, completed_count) do
    case current_phase(phase_cycle, completed_count) do
      nil -> %{}
      phase when snapshot.room.phase == phase -> %{}
      phase -> %{phase: phase}
    end
  end

  defp phase_cycle(%RoomSnapshot{} = snapshot) do
    case get_in(snapshot.room.config, ["phase_cycle"]) do
      phases when is_list(phases) and phases != [] -> Enum.filter(phases, &is_binary/1)
      _other -> @default_phase_cycle
    end
  end

  defp phase_cycle_from_state(policy_state) do
    case Map.get(policy_state, :phase_cycle) || Map.get(policy_state, "phase_cycle") do
      phases when is_list(phases) and phases != [] -> Enum.filter(phases, &is_binary/1)
      _other -> @default_phase_cycle
    end
  end

  defp assignment_limit(%RoomSnapshot{} = snapshot) do
    case get_in(snapshot.room.config, ["assignment_limit"]) do
      value when is_integer(value) and value > 0 ->
        value

      _other ->
        snapshot
        |> agent_participants()
        |> length()
        |> max(1)
        |> Kernel.*(3)
    end
  end

  defp assignment_limit_from_state(snapshot, policy_state) do
    case Map.get(policy_state, :assignment_limit) || Map.get(policy_state, "assignment_limit") do
      value when is_integer(value) and value > 0 -> value
      _other -> assignment_limit(snapshot)
    end
  end

  defp agent_participants(%RoomSnapshot{} = snapshot) do
    Enum.filter(snapshot.participants, &(&1.kind == "agent"))
  end

  defp available_rotation(participants, availability, cursor) do
    participants
    |> rotate(cursor)
    |> Enum.filter(&Map.has_key?(availability, &1.id))
  end

  defp rotate([], _cursor), do: []

  defp rotate(list, cursor) when is_integer(cursor) and cursor > 0 do
    offset = rem(cursor, length(list))
    Enum.drop(list, offset) ++ Enum.take(list, offset)
  end

  defp rotate(list, _cursor), do: list

  defp next_cursor([], _participant_id), do: 0

  defp next_cursor(participants, participant_id) do
    case Enum.find_index(participants, &(&1.id == participant_id)) do
      nil -> 0
      index -> index + 1
    end
  end

  defp active_assignment?(%RoomSnapshot{} = snapshot) do
    Enum.any?(snapshot.assignments, &(&1.status in ["pending", "active"]))
  end

  defp completed_assignment_count(%RoomSnapshot{} = snapshot) do
    Enum.count(snapshot.assignments, &(&1.status == "completed"))
  end

  defp current_phase([], _completed_count), do: nil

  defp current_phase(phases, completed_count) do
    Enum.at(phases, rem(completed_count, length(phases)))
  end
end
