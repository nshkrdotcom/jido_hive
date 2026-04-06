defmodule JidoHiveServer.Collaboration.DispatchPolicies.ResourcePool do
  @moduledoc false

  @behaviour JidoHiveServer.Collaboration.DispatchPolicy

  alias JidoHiveServer.Collaboration.ContextView

  @policy_id "resource_pool/v1"

  @default_phases [
    %{
      "phase" => "analysis",
      "objective" => "Analyze the brief and add room context.",
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
        assignment_count: nil,
        phases: @default_phases
      }
    }
  end

  @impl true
  def init_state(snapshot) do
    assignment_count =
      snapshot
      |> Map.get(:dispatch_policy_config, %{})
      |> Map.get("assignment_count")
      |> case do
        count when is_integer(count) and count > 0 -> count
        _other -> max(1, length(runtime_participants(snapshot)))
      end

    %{
      applied_event_ids: [],
      completed_slots: 0,
      total_slots: assignment_count,
      phases: phases(snapshot)
    }
  end

  @impl true
  def next_assignment(snapshot, available_target_ids) do
    participants =
      snapshot
      |> runtime_participants()
      |> Enum.filter(&(&1.target_id in available_target_ids))

    cond do
      participants == [] ->
        {:blocked, "blocked"}

      completed_slots(snapshot) >= total_slots(snapshot) ->
        {:blocked, "publication_ready"}

      true ->
        participant = Enum.min_by(participants, &assignment_count(snapshot, &1.participant_id))

        phase =
          Enum.at(phases(snapshot), rem(completed_slots(snapshot), length(phases(snapshot))))

        {:ok,
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
             allowed_relation_types:
               phase["allowed_relation_types"] || ["derives_from", "references"],
             authority_mode: phase["authority_mode"] || "advisory_only",
             format: "json_object"
           },
           context_view: ContextView.build(snapshot, participant),
           plan_slot_index: completed_slots(snapshot)
         }}
    end
  end

  @impl true
  def next_action(snapshot, available_target_ids) do
    cond do
      current_assignment?(snapshot) -> {:blocked, "running"}
      completed_slots(snapshot) >= total_slots(snapshot) -> {:complete, "publication_ready"}
      true -> next_assignment(snapshot, available_target_ids)
    end
  end

  @impl true
  def status(snapshot) do
    cond do
      failed_assignment?(snapshot) ->
        "failed"

      current_assignment?(snapshot) ->
        "running"

      completed_slots(snapshot) >= total_slots(snapshot) and total_slots(snapshot) > 0 ->
        "publication_ready"

      completed_slots(snapshot) > 0 ->
        "running"

      true ->
        snapshot.status || "idle"
    end
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

  defp assignment_count(snapshot, participant_id) do
    snapshot
    |> Map.get(:assignments, [])
    |> Enum.count(fn assignment ->
      Map.get(assignment, :participant_id) == participant_id and
        Map.get(assignment, :status) in ["completed", "failed", "abandoned"]
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
end
