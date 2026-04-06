defmodule JidoHiveServer.Collaboration.DispatchPolicies.HumanGate do
  @moduledoc false

  @behaviour JidoHiveServer.Collaboration.DispatchPolicy

  alias JidoHiveServer.Collaboration.ContextView

  @policy_id "human_gate/v1"

  @default_phases [
    %{
      "phase" => "analysis",
      "objective" => "Prepare context for human review.",
      "allowed_contribution_types" => ["reasoning"],
      "allowed_object_types" => ["belief", "note", "question"],
      "allowed_relation_types" => ["derives_from", "references"]
    }
  ]

  def id, do: @policy_id

  @impl true
  def definition do
    %{
      policy_id: @policy_id,
      config: %{
        phases: @default_phases,
        authority_participant_role: "reviewer"
      }
    }
  end

  @impl true
  def init_state(snapshot) do
    participants = runtime_participants(snapshot)
    phases = phases(snapshot)

    %{
      applied_event_ids: [],
      completed_slots: 0,
      total_slots: length(participants) * length(phases),
      phases: phases
    }
  end

  @impl true
  def next_assignment(snapshot, available_target_ids) do
    participants = runtime_participants(snapshot)
    phases = phases(snapshot)
    completed_slots = completed_slots(snapshot)
    total_slots = length(participants) * length(phases)

    with :ok <- require_runtime_participants(participants),
         :ok <- require_remaining_slots(completed_slots, total_slots, snapshot),
         {:ok, participant, phase} <- select_slot(participants, phases, completed_slots),
         :ok <- require_available_target(participant, available_target_ids) do
      {:ok, build_assignment(snapshot, participant, phase, completed_slots)}
    else
      {:blocked, reason} -> {:blocked, reason}
    end
  end

  @impl true
  def next_action(snapshot, available_target_ids) do
    cond do
      current_assignment?(snapshot) ->
        {:blocked, "running"}

      completed_slots(snapshot) < total_slots(snapshot) ->
        next_assignment(snapshot, available_target_ids)

      binding_contribution?(snapshot) ->
        {:complete, "publication_ready"}

      true ->
        {:awaiting_authority, "awaiting_authority"}
    end
  end

  @impl true
  def status(snapshot) do
    cond do
      failed_assignment?(snapshot) ->
        "failed"

      current_assignment?(snapshot) ->
        "running"

      completed_slots(snapshot) >= total_slots(snapshot) and binding_contribution?(snapshot) ->
        "publication_ready"

      completed_slots(snapshot) >= total_slots(snapshot) ->
        "awaiting_authority"

      completed_slots(snapshot) > 0 ->
        "running"

      true ->
        snapshot.status || "idle"
    end
  end

  defp binding_contribution?(snapshot) do
    Enum.any?(
      Map.get(snapshot, :contributions, []),
      &(Map.get(&1, :authority_level) == "binding")
    )
  end

  defp phases(snapshot) do
    snapshot
    |> Map.get(:dispatch_state, %{})
    |> Map.get(:phases) ||
      snapshot
      |> Map.get(:dispatch_policy_config, %{})
      |> Map.get("phases", @default_phases)
  end

  defp runtime_participants(snapshot) do
    snapshot
    |> Map.get(:participants, [])
    |> Enum.filter(fn participant ->
      Map.get(participant, :participant_kind) == "runtime" and
        is_binary(Map.get(participant, :target_id))
    end)
  end

  defp completed_slots(snapshot) do
    snapshot
    |> Map.get(:dispatch_state, %{})
    |> Map.get(:completed_slots, 0)
  end

  defp total_slots(snapshot) do
    snapshot
    |> Map.get(:dispatch_state, %{})
    |> Map.get(:total_slots, 0)
  end

  defp current_assignment?(snapshot), do: Map.get(snapshot, :current_assignment, %{}) != %{}

  defp failed_assignment?(snapshot) do
    Enum.any?(Map.get(snapshot, :assignments, []), &(&1.status == "failed"))
  end

  defp require_runtime_participants([]), do: {:blocked, "awaiting_authority"}
  defp require_runtime_participants(_participants), do: :ok

  defp require_remaining_slots(completed_slots, total_slots, snapshot) do
    if completed_slots >= total_slots, do: {:blocked, status(snapshot)}, else: :ok
  end

  defp select_slot(participants, phases, completed_slots) do
    participant_count = length(participants)
    phase = Enum.at(phases, div(completed_slots, participant_count)) || List.last(phases)
    participant = Enum.at(participants, rem(completed_slots, participant_count))
    {:ok, participant, phase}
  end

  defp require_available_target(participant, available_target_ids) do
    if Map.get(participant, :target_id) in available_target_ids,
      do: :ok,
      else: {:blocked, "blocked"}
  end

  defp build_assignment(snapshot, participant, phase, completed_slots) do
    %{
      participant_id: Map.get(participant, :participant_id),
      participant_role: Map.get(participant, :participant_role),
      target_id: Map.get(participant, :target_id),
      capability_id: Map.get(participant, :capability_id),
      phase: phase["phase"],
      objective: phase["objective"] || snapshot.brief,
      contribution_contract: %{
        allowed_contribution_types: phase["allowed_contribution_types"] || ["reasoning"],
        allowed_object_types: phase["allowed_object_types"] || ["belief", "note"],
        allowed_relation_types: phase["allowed_relation_types"] || ["derives_from", "references"],
        authority_mode: "advisory_only",
        format: "json_object"
      },
      context_view: ContextView.build(snapshot, participant),
      plan_slot_index: completed_slots
    }
  end
end
