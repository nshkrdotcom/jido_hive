defmodule JidoHiveServer.Collaboration.Referee do
  @moduledoc false

  alias JidoHiveServer.Collaboration.ExecutionPlan

  @spec next_assignment(map(), [String.t()] | nil) :: {:ok, map()} | {:error, atom()} | :halt
  def next_assignment(snapshot, available_target_ids \\ nil)

  def next_assignment(%{current_turn: current_turn}, _available_target_ids)
      when map_size(current_turn) > 0,
      do: :halt

  def next_assignment(snapshot, available_target_ids) when is_map(snapshot) do
    with {:ok, %{execution_plan: plan} = snapshot} <- ExecutionPlan.ensure(snapshot),
         false <- ExecutionPlan.done?(plan) do
      available_target_ids =
        available_target_ids || Enum.map(plan.locked_participants, & &1.target_id)

      case ExecutionPlan.select_next_participant(plan, available_target_ids) do
        {:ok, participant, slot_index} ->
          build_assignment(snapshot, plan, participant, slot_index)

        :none ->
          {:error, :no_available_participants}
      end
    else
      true ->
        :halt

      {:error, _} = error ->
        error
    end
  end

  @spec room_status(map()) :: String.t()
  def room_status(snapshot) when is_map(snapshot) do
    cond do
      current_turn_running?(snapshot) ->
        "running"

      pending_turns?(snapshot) ->
        "in_progress"

      open_disputes(snapshot) != [] ->
        "needs_resolution"

      publish_requested?(snapshot) and
          Map.get(snapshot.execution_plan || %{}, :completed_turn_count, 0) > 0 ->
        "publication_ready"

      Map.get(snapshot, :turns, []) != [] ->
        "in_review"

      true ->
        "idle"
    end
  end

  @spec phase(map()) :: String.t()
  def phase(snapshot) when is_map(snapshot) do
    case next_assignment(snapshot) do
      {:ok, assignment} ->
        assignment.phase

      {:error, :no_available_participants} ->
        snapshot
        |> Map.get(:execution_plan, %{})
        |> ExecutionPlan.stage_for_turn()
        |> Map.get(:phase, "idle")

      :halt ->
        if room_status(snapshot) == "publication_ready", do: "publication_ready", else: "idle"
    end
  end

  @spec open_disputes(map()) :: [map()]
  def open_disputes(snapshot) when is_map(snapshot) do
    snapshot
    |> Map.get(:disputes, [])
    |> Enum.filter(&(&1.status == :open))
  end

  @spec publish_requested?(map()) :: boolean()
  def publish_requested?(snapshot) when is_map(snapshot) do
    snapshot
    |> Map.get(:context_entries, [])
    |> Enum.any?(&(&1.entry_type == "publish_request"))
  end

  @spec directives(String.t(), map(), keyword()) :: [String.t()]
  def directives("proposal", snapshot, _opts) do
    [
      "Add at least one CLAIM and one EVIDENCE action grounded in the brief and the current shared state.",
      "If the room should be published after review, emit one PUBLISH action.",
      "Build on prior claims instead of restating the room from scratch."
    ] ++ room_rule_directives(snapshot)
  end

  def directives("critique", snapshot, _opts) do
    [
      "Critique the current shared claims and evidence against the brief and rules.",
      "Use OBJECT actions with targeted entry_ref values when a claim or evidence item is weak, redundant, or missing support.",
      "If no objection is needed, emit one DECIDE action that records what remains sound."
    ] ++ room_rule_directives(snapshot)
  end

  def directives("resolution", snapshot, opts) do
    dispute_ids =
      opts
      |> Keyword.get(:open_disputes, [])
      |> Enum.map_join(", ", & &1.dispute_id)

    [
      "Resolve every open dispute by targeting its dispute_id with REVISE or DECIDE actions.",
      "If there are no open disputes, consolidate the best current direction with DECIDE actions.",
      "Only mark the room publishable if the synthesis is concrete and actionable."
      | if(dispute_ids == "", do: [], else: ["Open disputes: #{dispute_ids}"])
    ] ++ room_rule_directives(snapshot)
  end

  def directives(_phase, snapshot, _opts), do: room_rule_directives(snapshot)

  defp build_assignment(snapshot, plan, participant, slot_index) do
    stage = ExecutionPlan.stage_for_turn(plan)
    round = Map.get(plan, :completed_turn_count, 0) + 1
    opts = [open_disputes: open_disputes(snapshot)]

    {:ok,
     %{
       phase: stage.phase,
       round: round,
       plan_slot_index: slot_index,
       participant_id: participant.participant_id,
       participant_role: stage.participant_role,
       target_id: participant.target_id,
       capability_id: participant.capability_id,
       objective: objective(stage.phase, snapshot, round, plan),
       directives: directives(stage.phase, snapshot, opts),
       open_disputes: Keyword.get(opts, :open_disputes, [])
     }}
  end

  defp objective("proposal", snapshot, round, plan),
    do:
      "Proposal pass #{round}/#{plan.planned_turn_count}: add concrete claims and evidence for: #{snapshot.brief}"

  defp objective("critique", snapshot, round, plan),
    do:
      "Critique pass #{round}/#{plan.planned_turn_count}: review the accumulated proposal state for: #{snapshot.brief}"

  defp objective("resolution", snapshot, round, plan),
    do:
      "Resolution pass #{round}/#{plan.planned_turn_count}: resolve disputes or consolidate the final plan for: #{snapshot.brief}"

  defp objective(_phase, snapshot, _round, _plan), do: snapshot.brief

  defp current_turn_running?(snapshot) do
    snapshot
    |> Map.get(:current_turn, %{})
    |> map_size()
    |> Kernel.>(0)
  end

  defp room_rule_directives(snapshot) do
    snapshot
    |> Map.get(:rules, [])
    |> Enum.map(&"Rule: #{&1}")
  end

  defp pending_turns?(snapshot) do
    case ExecutionPlan.ensure(snapshot) do
      {:ok, %{execution_plan: plan}} -> not ExecutionPlan.done?(plan)
      {:error, _} -> false
    end
  end
end
