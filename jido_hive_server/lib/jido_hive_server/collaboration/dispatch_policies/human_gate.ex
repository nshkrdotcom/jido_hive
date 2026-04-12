defmodule JidoHiveServer.Collaboration.DispatchPolicies.HumanGate do
  @moduledoc false

  @behaviour JidoHiveServer.Collaboration.DispatchPolicy

  alias JidoHiveServer.Collaboration.Schema.{Contribution, Participant, RoomEvent, RoomSnapshot}

  @policy_id "human_gate/v1"

  @impl true
  def id, do: @policy_id

  @impl true
  def definition do
    %{
      policy_id: @policy_id,
      config: %{
        agent_assignment_limit: "agent_count by default",
        phase_cycle: ["analysis", "review"]
      }
    }
  end

  @impl true
  def init(%RoomSnapshot{} = snapshot, _context) do
    {:ok,
     %{
       cursor: 0,
       agent_assignment_limit: agent_assignment_limit(snapshot),
       gate_assignment_id: nil,
       human_gate_satisfied: false,
       phase_cycle: ["analysis", "review"]
     }, %{}}
  end

  @impl true
  def handle_event(
        %RoomEvent{type: :assignment_completed, data: %{"assignment_id" => assignment_id}},
        %RoomSnapshot{} = snapshot,
        policy_state,
        _context
      ) do
    next_policy_state =
      if completed_agent_assignment_count(snapshot) >=
           agent_assignment_limit_from_state(snapshot, policy_state) do
        Map.put(policy_state, :gate_assignment_id, assignment_id)
      else
        policy_state
      end

    {:ok, next_policy_state, %{}}
  end

  @impl true
  def handle_event(
        %RoomEvent{type: :contribution_submitted},
        %RoomSnapshot{} = snapshot,
        policy_state,
        _context
      ) do
    next_policy_state =
      if human_gate_satisfied?(snapshot, policy_state) do
        Map.put(policy_state, :human_gate_satisfied, true)
      else
        policy_state
      end

    {:ok, next_policy_state, %{}}
  end

  @impl true
  def handle_event(_event, _snapshot, policy_state, _context), do: {:ok, policy_state, %{}}

  @impl true
  def select(%RoomSnapshot{} = snapshot, %{availability: availability, policy_state: policy_state}) do
    cond do
      snapshot.room.status in ["closed", "failed"] ->
        {:close, String.to_atom(snapshot.room.status), policy_state, %{}}

      snapshot.room.status == "completed" ->
        {:complete, %{reason: :already_completed}, policy_state, %{}}

      active_assignment?(snapshot) ->
        {:wait, :assignment_in_progress, policy_state, %{status: "active"}}

      completed_agent_assignment_count(snapshot) <
          agent_assignment_limit_from_state(snapshot, policy_state) ->
        select_agent_assignment(snapshot, availability, policy_state)

      human_gate_satisfied?(snapshot, policy_state) ->
        {:complete, %{reason: :human_gate_satisfied},
         Map.put(policy_state, :human_gate_satisfied, true),
         %{status: "completed", phase: "review"}}

      true ->
        {:wait, :awaiting_human, policy_state, %{status: "waiting", phase: "review"}}
    end
  end

  defp select_agent_assignment(snapshot, availability, policy_state) do
    participants = agent_participants(snapshot)

    case available_rotation(participants, availability, Map.get(policy_state, :cursor, 0)) do
      [] ->
        {:wait, :no_available_participants, policy_state, %{status: "waiting"}}

      [%Participant{id: participant_id} | _rest] ->
        next_policy_state =
          policy_state
          |> Map.put(:cursor, next_cursor(participants, participant_id))
          |> Map.put(:human_gate_satisfied, false)

        {:dispatch, [participant_id], next_policy_state, %{status: "active", phase: "analysis"}}
    end
  end

  defp human_gate_satisfied?(%RoomSnapshot{} = snapshot, policy_state) do
    gate_assignment_id =
      Map.get(policy_state, :gate_assignment_id) || Map.get(policy_state, "gate_assignment_id")

    Enum.any?(snapshot.contributions, fn
      %Contribution{participant_id: participant_id, assignment_id: assignment_id} ->
        human_participant?(snapshot, participant_id) and
          (is_nil(gate_assignment_id) or assignment_id == gate_assignment_id)
    end)
  end

  defp human_participant?(%RoomSnapshot{} = snapshot, participant_id) do
    Enum.any?(snapshot.participants, &(&1.id == participant_id and &1.kind == "human"))
  end

  defp agent_assignment_limit(%RoomSnapshot{} = snapshot) do
    case get_in(snapshot.room.config, ["agent_assignment_limit"]) do
      value when is_integer(value) and value > 0 -> value
      _other -> max(length(agent_participants(snapshot)), 1)
    end
  end

  defp agent_assignment_limit_from_state(snapshot, policy_state) do
    case Map.get(policy_state, :agent_assignment_limit) ||
           Map.get(policy_state, "agent_assignment_limit") do
      value when is_integer(value) and value > 0 -> value
      _other -> agent_assignment_limit(snapshot)
    end
  end

  defp completed_agent_assignment_count(%RoomSnapshot{} = snapshot) do
    snapshot.assignments
    |> Enum.count(fn assignment ->
      assignment.status == "completed" and
        not human_participant?(snapshot, assignment.participant_id)
    end)
  end

  defp active_assignment?(%RoomSnapshot{} = snapshot) do
    Enum.any?(snapshot.assignments, &(&1.status in ["pending", "active"]))
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
end
