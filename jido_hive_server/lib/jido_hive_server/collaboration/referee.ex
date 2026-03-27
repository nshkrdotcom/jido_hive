defmodule JidoHiveServer.Collaboration.Referee do
  @moduledoc false

  @spec next_assignment(map()) :: {:ok, map()} | :halt
  def next_assignment(%{current_turn: current_turn}) when map_size(current_turn) > 0, do: :halt

  def next_assignment(snapshot) when is_map(snapshot) do
    turns = Map.get(snapshot, :turns, [])
    open_disputes = open_disputes(snapshot)

    cond do
      turns == [] ->
        build_assignment(
          snapshot,
          primary_participant(snapshot),
          "proposal",
          current_round(snapshot) + 1
        )

      length(turns) == 1 ->
        build_assignment(
          snapshot,
          skeptic_participant(snapshot),
          "critique",
          current_round(snapshot) + 1
        )

      open_disputes != [] ->
        build_assignment(
          snapshot,
          primary_participant(snapshot),
          "resolution",
          current_round(snapshot) + 1,
          open_disputes: open_disputes
        )

      publish_requested?(snapshot) ->
        :halt

      true ->
        :halt
    end
  end

  @spec room_status(map()) :: String.t()
  def room_status(snapshot) when is_map(snapshot) do
    turns = Map.get(snapshot, :turns, [])

    cond do
      current_turn_running?(snapshot) ->
        "running"

      open_disputes(snapshot) != [] ->
        "needs_resolution"

      publish_requested?(snapshot) and length(turns) >= 2 ->
        "publication_ready"

      turns != [] ->
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
      "Emit at least one CLAIM and one EVIDENCE action grounded in the shared brief.",
      "If the room should be published after review, emit one PUBLISH action.",
      "Carry forward only durable shared facts from prior turns."
    ] ++ room_rule_directives(snapshot)
  end

  def directives("critique", snapshot, _opts) do
    [
      "Critique the current claims and evidence against the brief and rules.",
      "Use OBJECT actions with targeted entry_ref values when a claim or evidence item is weak.",
      "If no objection is needed, emit one DECIDE action that states the proposal is acceptable."
    ] ++ room_rule_directives(snapshot)
  end

  def directives("resolution", snapshot, opts) do
    dispute_ids =
      opts
      |> Keyword.get(:open_disputes, [])
      |> Enum.map_join(", ", & &1.dispute_id)

    [
      "Resolve every open dispute by targeting its dispute_id with REVISE or DECIDE actions.",
      "Preserve the original objection in the room history and answer it explicitly.",
      "Only mark the room publishable if the dispute resolution is concrete."
      | if(dispute_ids == "", do: [], else: ["Open disputes: #{dispute_ids}"])
    ] ++ room_rule_directives(snapshot)
  end

  def directives(_phase, snapshot, _opts), do: room_rule_directives(snapshot)

  defp build_assignment(snapshot, participant, phase, round),
    do: build_assignment(snapshot, participant, phase, round, [])

  defp build_assignment(_snapshot, nil, _phase, _round, _opts), do: :halt

  defp build_assignment(snapshot, participant, phase, round, opts) do
    {:ok,
     %{
       phase: phase,
       round: round,
       participant_id: participant.participant_id,
       participant_role: participant.role,
       target_id: participant.target_id,
       capability_id: participant.capability_id,
       objective: objective(phase, snapshot),
       directives: directives(phase, snapshot, opts),
       open_disputes: Keyword.get(opts, :open_disputes, [])
     }}
  end

  defp objective("proposal", snapshot),
    do: "Propose a concrete collaboration design for: #{snapshot.brief}"

  defp objective("critique", snapshot),
    do: "Critique the current proposal for: #{snapshot.brief}"

  defp objective("resolution", _snapshot),
    do: "Resolve the currently open disputes and prepare the room for publication."

  defp objective(_phase, snapshot), do: snapshot.brief

  defp primary_participant(snapshot) do
    Enum.find(Map.get(snapshot, :participants, []), &(&1.role == "architect")) ||
      List.first(Map.get(snapshot, :participants, []))
  end

  defp skeptic_participant(snapshot) do
    Enum.find(Map.get(snapshot, :participants, []), &(&1.role == "skeptic")) ||
      Map.get(snapshot, :participants, []) |> Enum.at(1) ||
      primary_participant(snapshot)
  end

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

  defp current_round(snapshot), do: Map.get(snapshot, :round, 0)
end
