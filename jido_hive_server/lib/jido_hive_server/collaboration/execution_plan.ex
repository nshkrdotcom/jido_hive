defmodule JidoHiveServer.Collaboration.ExecutionPlan do
  @moduledoc false

  @max_participants 39

  @stages [
    %{phase: "proposal", participant_role: "proposer"},
    %{phase: "critique", participant_role: "critic"},
    %{phase: "resolution", participant_role: "resolver"}
  ]

  @spec max_participants() :: pos_integer()
  def max_participants, do: @max_participants

  @spec stage_count() :: pos_integer()
  def stage_count, do: length(@stages)

  @spec new([map()]) :: {:ok, map()} | {:error, atom()}
  def new(participants) when is_list(participants) do
    normalized = Enum.map(participants, &normalize_participant/1)

    with :ok <- validate_count(normalized),
         :ok <- validate_uniqueness(normalized, :participant_id, :duplicate_participant_id),
         :ok <- validate_uniqueness(normalized, :target_id, :duplicate_target_id) do
      participant_count = length(normalized)

      {:ok,
       %{
         strategy: "round_robin",
         max_participants: @max_participants,
         stage_count: stage_count(),
         participant_count: participant_count,
         planned_turn_count: participant_count * stage_count(),
         completed_turn_count: 0,
         round_robin_index: 0,
         excluded_target_ids: [],
         started_at: nil,
         locked_participants: normalized
       }}
    end
  end

  @spec ensure(map()) :: {:ok, map()} | {:error, atom()}
  def ensure(%{execution_plan: plan} = snapshot) when is_map(plan) and map_size(plan) > 0,
    do: {:ok, snapshot}

  def ensure(%{participants: participants} = snapshot) when is_list(participants) do
    with {:ok, plan} <- new(participants) do
      {:ok, Map.put(snapshot, :execution_plan, plan)}
    end
  end

  def ensure(_snapshot), do: {:error, :participant_count_out_of_bounds}

  @spec done?(map()) :: boolean()
  def done?(plan) when is_map(plan) do
    Map.get(plan, :completed_turn_count, 0) >= Map.get(plan, :planned_turn_count, 0)
  end

  @spec stage_for_turn(map(), non_neg_integer() | nil) :: map()
  def stage_for_turn(plan, turn_index \\ nil) when is_map(plan) do
    participant_count = max(Map.get(plan, :participant_count, 1), 1)
    completed_turn_count = Map.get(plan, :completed_turn_count, 0)
    index = turn_index || completed_turn_count
    stage_index = min(div(index, participant_count), stage_count() - 1)
    Enum.at(@stages, stage_index)
  end

  @spec select_next_participant(map(), [String.t()]) ::
          {:ok, map(), non_neg_integer()} | :none
  def select_next_participant(plan, available_target_ids)
      when is_map(plan) and is_list(available_target_ids) do
    excluded = MapSet.new(Map.get(plan, :excluded_target_ids, []))
    available = available_target_ids |> MapSet.new() |> MapSet.difference(excluded)
    participants = Map.get(plan, :locked_participants, [])
    participant_count = length(participants)

    cond do
      participant_count == 0 ->
        :none

      MapSet.size(available) == 0 ->
        :none

      true ->
        start_index = normalize_index(Map.get(plan, :round_robin_index, 0), participant_count)

        0..(participant_count - 1)
        |> Enum.find_value(:none, fn offset ->
          slot_index = rem(start_index + offset, participant_count)
          participant = Enum.at(participants, slot_index)
          available_participant(participant, available, slot_index)
        end)
    end
  end

  @spec record_open(map(), non_neg_integer()) :: map()
  def record_open(plan, slot_index) when is_map(plan) and is_integer(slot_index) do
    participant_count = max(Map.get(plan, :participant_count, 1), 1)

    %{
      plan
      | round_robin_index: rem(slot_index + 1, participant_count),
        started_at: Map.get(plan, :started_at) || DateTime.utc_now()
    }
  end

  @spec record_completion(map()) :: map()
  def record_completion(plan) when is_map(plan) do
    completed_turn_count = Map.get(plan, :completed_turn_count, 0)
    planned_turn_count = Map.get(plan, :planned_turn_count, completed_turn_count)

    %{plan | completed_turn_count: min(completed_turn_count + 1, planned_turn_count)}
  end

  @spec record_abandon(map(), String.t()) :: map()
  def record_abandon(plan, target_id) when is_map(plan) and is_binary(target_id) do
    excluded_target_ids =
      plan
      |> Map.get(:excluded_target_ids, [])
      |> Kernel.++([target_id])
      |> Enum.uniq()

    Map.put(plan, :excluded_target_ids, excluded_target_ids)
  end

  defp normalize_participant(%{} = participant) do
    %{
      participant_id: participant[:participant_id] || participant["participant_id"],
      role: participant[:role] || participant["role"] || "worker",
      target_id: participant[:target_id] || participant["target_id"],
      capability_id: participant[:capability_id] || participant["capability_id"]
    }
  end

  defp validate_count(participants) do
    count = length(participants)

    if count >= 1 and count <= @max_participants do
      :ok
    else
      {:error, :participant_count_out_of_bounds}
    end
  end

  defp validate_uniqueness(participants, key, error_reason) do
    values =
      participants
      |> Enum.map(&Map.get(&1, key))
      |> Enum.reject(&is_nil/1)

    if length(values) == length(Enum.uniq(values)) do
      :ok
    else
      {:error, error_reason}
    end
  end

  defp available_participant(nil, _available, _slot_index), do: nil

  defp available_participant(participant, available, slot_index) do
    if MapSet.member?(available, participant.target_id) do
      {:ok, participant, slot_index}
    end
  end

  defp normalize_index(index, participant_count) do
    if participant_count <= 0 do
      0
    else
      rem(max(index, 0), participant_count)
    end
  end
end
