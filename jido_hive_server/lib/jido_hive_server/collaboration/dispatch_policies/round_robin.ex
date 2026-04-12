defmodule JidoHiveServer.Collaboration.DispatchPolicies.RoundRobin do
  @moduledoc false

  @behaviour JidoHiveServer.Collaboration.DispatchPolicy

  alias JidoHiveContextGraph
  alias JidoHiveServer.Collaboration.DispatchPhaseConfig

  @policy_id "round_robin/v2"

  @default_phases [
    %{
      "phase" => "analysis",
      "objective" => "Analyze the brief and add room-scoped context.",
      "allowed_contribution_types" => ["reasoning"],
      "allowed_object_types" => ["belief", "note", "question"],
      "allowed_relation_types" => ["derives_from", "references", "contradicts"]
    },
    %{
      "phase" => "critique",
      "objective" => "Critique the current room context and surface gaps.",
      "allowed_contribution_types" => ["reasoning", "constraint"],
      "allowed_object_types" => ["question", "constraint", "note"],
      "allowed_relation_types" => ["contradicts", "references", "derives_from"]
    },
    %{
      "phase" => "synthesis",
      "objective" => "Synthesize the current context into decisions or artifacts.",
      "allowed_contribution_types" => ["reasoning", "decision", "artifact"],
      "allowed_object_types" => ["decision", "artifact", "note"],
      "allowed_relation_types" => ["derives_from", "references", "resolves"]
    }
  ]

  def id, do: @policy_id

  @impl true
  def definition do
    %{
      policy_id: @policy_id,
      config: %{
        phases: @default_phases
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
      participant_ids: Enum.map(participants, & &1.participant_id),
      phases: phases
    }
  end

  @impl true
  def next_assignment(snapshot, available_target_ids) do
    participants = runtime_participants(snapshot)
    phases = phases(snapshot)
    completed_slots = completed_slots(snapshot)

    cond do
      participants == [] ->
        {:blocked, "blocked"}

      completed_slots >= total_slots(snapshot, participants, phases) ->
        {:blocked, "publication_ready"}

      true ->
        participant_count = length(participants)
        phase = Enum.at(phases, div(completed_slots, participant_count)) || List.last(phases)
        start_index = rem(completed_slots, participant_count)
        ordered = rotate(participants, start_index)

        case Enum.find(ordered, &(Map.get(&1, :target_id) in available_target_ids)) do
          nil -> {:blocked, "blocked"}
          participant -> {:ok, build_assignment(snapshot, participant, phase, completed_slots)}
        end
    end
  end

  @impl true
  def next_action(snapshot, available_target_ids) do
    cond do
      current_assignment?(snapshot) ->
        {:blocked, "running"}

      completed_slots(snapshot) >=
          total_slots(snapshot, runtime_participants(snapshot), phases(snapshot)) ->
        {:complete, "publication_ready"}

      true ->
        next_assignment(snapshot, available_target_ids)
    end
  end

  @impl true
  def status(snapshot) do
    cond do
      failed_assignment?(snapshot) ->
        "failed"

      current_assignment?(snapshot) ->
        "running"

      completed_slots(snapshot) >=
        total_slots(snapshot, runtime_participants(snapshot), phases(snapshot)) and
          total_slots(snapshot, runtime_participants(snapshot), phases(snapshot)) > 0 ->
        "publication_ready"

      completed_slots(snapshot) > 0 ->
        "running"

      true ->
        snapshot.status || "idle"
    end
  end

  defp build_assignment(snapshot, participant, phase, slot_index) do
    task_context = assignment_task_context(snapshot, phase)

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
        authority_mode: phase["authority_mode"] || "advisory_only",
        format: "json_object"
      },
      task_context: task_context,
      context_view: JidoHiveContextGraph.build_context_view(snapshot, participant, task_context),
      plan_slot_index: slot_index
    }
  end

  defp assignment_task_context(snapshot, phase) do
    %{
      mode: :assignment,
      anchor_context_id: latest_context_id(snapshot),
      objective: phase["objective"] || snapshot.brief
    }
  end

  defp phases(snapshot) do
    snapshot
    |> raw_phases()
    |> DispatchPhaseConfig.normalize(@default_phases)
  end

  defp raw_phases(snapshot) do
    snapshot
    |> Map.get(:dispatch_state, %{})
    |> Map.get(:phases) ||
      snapshot
      |> Map.get(:dispatch_policy_config, %{})
      |> then(&(Map.get(&1, "phases") || Map.get(&1, :phases)))
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

  defp total_slots(snapshot, participants, phases) do
    snapshot
    |> Map.get(:dispatch_state, %{})
    |> Map.get(:total_slots, length(participants) * length(phases))
  end

  defp current_assignment?(snapshot), do: Map.get(snapshot, :current_assignment, %{}) != %{}

  defp failed_assignment?(snapshot) do
    Enum.any?(Map.get(snapshot, :assignments, []), &(&1.status == "failed"))
  end

  defp latest_context_id(snapshot) do
    snapshot
    |> Map.get(:context_objects, [])
    |> Enum.max_by(&{Map.get(&1, :inserted_at), Map.get(&1, :context_id)}, fn -> nil end)
    |> case do
      nil -> nil
      context_object -> Map.get(context_object, :context_id)
    end
  end

  defp rotate(list, 0), do: list
  defp rotate([], _index), do: []
  defp rotate(list, index), do: Enum.drop(list, index) ++ Enum.take(list, index)
end
