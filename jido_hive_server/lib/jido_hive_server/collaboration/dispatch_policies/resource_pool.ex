defmodule JidoHiveServer.Collaboration.DispatchPolicies.ResourcePool do
  @moduledoc false

  @behaviour JidoHiveServer.Collaboration.DispatchPolicy

  alias JidoHiveServer.Collaboration.Schema.{Participant, RoomSnapshot}

  @policy_id "resource_pool/v1"

  @impl true
  def id, do: @policy_id

  @impl true
  def definition do
    %{
      policy_id: @policy_id,
      config: %{
        assignment_limit: "participant_count * 3 by default"
      }
    }
  end

  @impl true
  def init(%RoomSnapshot{} = snapshot, _context) do
    {:ok, %{assignment_limit: assignment_limit(snapshot)}, %{}}
  end

  @impl true
  def handle_event(_event, _snapshot, policy_state, _context), do: {:ok, policy_state, %{}}

  @impl true
  def select(%RoomSnapshot{} = snapshot, %{availability: availability, policy_state: policy_state}) do
    limit = Map.get(policy_state, :assignment_limit, assignment_limit(snapshot))

    cond do
      snapshot.room.status in ["closed", "failed"] ->
        {:close, String.to_atom(snapshot.room.status), policy_state, %{}}

      snapshot.room.status == "completed" ->
        {:complete, %{reason: :already_completed}, policy_state, %{}}

      completed_assignment_count(snapshot) >= limit ->
        {:complete, %{reason: :assignment_limit_reached}, policy_state, %{status: "completed"}}

      Enum.any?(snapshot.assignments, &(&1.status in ["pending", "active"])) ->
        {:wait, :assignment_in_progress, policy_state, %{status: "active"}}

      true ->
        case next_available_participant(snapshot, availability) do
          nil ->
            {:wait, :no_available_participants, policy_state, %{status: "waiting"}}

          %Participant{id: participant_id} ->
            {:dispatch, [participant_id], policy_state, %{status: "active"}}
        end
    end
  end

  defp assignment_limit(%RoomSnapshot{} = snapshot) do
    case get_in(snapshot.room.config, ["assignment_limit"]) do
      value when is_integer(value) and value > 0 -> value
      _other -> max(length(agent_participants(snapshot)), 1) * 3
    end
  end

  defp agent_participants(%RoomSnapshot{} = snapshot) do
    Enum.filter(snapshot.participants, &(&1.kind == "agent"))
  end

  defp next_available_participant(%RoomSnapshot{} = snapshot, availability) do
    snapshot
    |> agent_participants()
    |> Enum.filter(&Map.has_key?(availability, &1.id))
    |> Enum.min_by(&usage_count(snapshot, &1.id), fn -> nil end)
  end

  defp usage_count(%RoomSnapshot{} = snapshot, participant_id) do
    Enum.count(snapshot.assignments, &(&1.participant_id == participant_id))
  end

  defp completed_assignment_count(%RoomSnapshot{} = snapshot) do
    Enum.count(snapshot.assignments, &(&1.status == "completed"))
  end
end
