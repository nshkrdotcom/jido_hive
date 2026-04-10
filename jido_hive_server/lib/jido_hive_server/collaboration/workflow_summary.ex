defmodule JidoHiveServer.Collaboration.WorkflowSummary do
  @moduledoc false

  alias JidoHiveServer.Collaboration.{ContextDeduper, ContextGraph}

  @spec build(map()) :: map()
  def build(snapshot) when is_map(snapshot) do
    contradictions = contradiction_objects(snapshot)
    open_questions = ContextGraph.open_questions(snapshot)
    canonical_objects = ContextDeduper.canonical_context_objects(snapshot)
    duplicate_groups = ContextDeduper.duplicate_groups(snapshot)
    duplicate_count = Enum.reduce(duplicate_groups, 0, &(&2 + &1.duplicate_size - 1))
    stale_count = stale_count(snapshot)
    decision_count = Enum.count(canonical_objects, &(object_type(&1) == "decision"))
    status = room_status(snapshot)
    publish_ready = status == "publication_ready"

    %{
      objective: room_objective(snapshot),
      stage: workflow_stage(status, contradictions, open_questions, decision_count),
      next_action:
        workflow_next_action(
          status,
          contradictions,
          open_questions,
          decision_count,
          publish_ready
        ),
      blockers: blockers(status, contradictions, open_questions, decision_count, publish_ready),
      publish_ready: publish_ready,
      publish_blockers:
        publish_blockers(status, contradictions, open_questions, decision_count, publish_ready),
      graph_counts: %{
        total: length(canonical_objects),
        decisions: decision_count,
        questions: length(open_questions),
        contradictions: length(contradictions),
        duplicate_groups: length(duplicate_groups),
        duplicates: duplicate_count,
        stale: stale_count
      },
      focus_candidates: focus_candidates(contradictions, open_questions, duplicate_groups)
    }
  end

  def build(_snapshot) do
    %{
      objective: "No room objective available",
      stage: "Unavailable",
      next_action: "Refresh room data",
      blockers: [],
      publish_ready: false,
      publish_blockers: ["Room workflow is unavailable"],
      graph_counts: %{
        total: 0,
        decisions: 0,
        questions: 0,
        contradictions: 0,
        duplicate_groups: 0,
        duplicates: 0,
        stale: 0
      },
      focus_candidates: []
    }
  end

  defp workflow_stage("publication_ready", _contradictions, _open_questions, _decision_count),
    do: "Ready to publish"

  defp workflow_stage(_status, contradictions, _open_questions, _decision_count)
       when contradictions != [],
       do: "Resolve contradictions"

  defp workflow_stage(_status, _contradictions, open_questions, 0)
       when open_questions != [],
       do: "Clarify open questions"

  defp workflow_stage("idle", _contradictions, _open_questions, 0), do: "Start the room"
  defp workflow_stage(_status, _contradictions, _open_questions, 0), do: "Reach a decision"

  defp workflow_stage("running", _contradictions, _open_questions, _decision_count),
    do: "Steer active work"

  defp workflow_stage(status, _contradictions, _open_questions, _decision_count),
    do: humanize_status(status)

  defp workflow_next_action(
         "publication_ready",
         _contradictions,
         _open_questions,
         _decision_count,
         true
       ) do
    "Review the publication plan and submit to the selected channels"
  end

  defp workflow_next_action(
         _status,
         [contradiction | _rest],
         _open_questions,
         _decision_count,
         _publish_ready
       ) do
    "Review #{context_id(contradiction)} and submit a binding resolution"
  end

  defp workflow_next_action(
         _status,
         _contradictions,
         [question | _rest],
         _decision_count,
         _publish_ready
       ) do
    "Answer #{context_id(question)} or send a clarification message that closes it"
  end

  defp workflow_next_action("idle", _contradictions, _open_questions, 0, _publish_ready) do
    "Start a room run or send the first steering message"
  end

  defp workflow_next_action(_status, _contradictions, _open_questions, 0, _publish_ready) do
    "Send a steering message that drives the room toward a concrete decision"
  end

  defp workflow_next_action(
         "running",
         _contradictions,
         _open_questions,
         _decision_count,
         _publish_ready
       ) do
    "Monitor new contributions and steer only if progress stalls"
  end

  defp workflow_next_action(
         _status,
         _contradictions,
         _open_questions,
         _decision_count,
         _publish_ready
       ) do
    "Inspect the shared graph and accept or publish the strongest decision"
  end

  defp blockers(_status, contradictions, open_questions, decision_count, publish_ready) do
    []
    |> maybe_add_blocker(contradictions != [], %{
      kind: "contradiction",
      count: length(contradictions)
    })
    |> maybe_add_blocker(
      open_questions != [],
      %{kind: "open_question", count: length(open_questions)}
    )
    |> maybe_add_blocker(
      not publish_ready and decision_count == 0,
      %{kind: "missing_decision", count: 1}
    )
  end

  defp publish_blockers(_status, _contradictions, _open_questions, _decision_count, true), do: []

  defp publish_blockers(_status, contradictions, open_questions, decision_count, false) do
    []
    |> maybe_add_message(contradictions != [], "Open contradictions remain")
    |> maybe_add_message(open_questions != [], "Open questions remain")
    |> maybe_add_message(decision_count == 0, "No decision has been recorded")
  end

  defp focus_candidates(contradictions, open_questions, duplicate_groups) do
    contradiction_focus =
      Enum.map(contradictions, fn object ->
        %{kind: "contradiction", context_id: context_id(object)}
      end)

    question_focus =
      Enum.map(open_questions, fn object ->
        %{kind: "question", context_id: context_id(object)}
      end)

    duplicate_focus =
      Enum.map(duplicate_groups, fn group ->
        %{
          kind: "duplicate_cluster",
          context_id: group.canonical_context_id,
          duplicate_count: group.duplicate_size - 1
        }
      end)

    (contradiction_focus ++ question_focus ++ duplicate_focus)
    |> Enum.take(8)
  end

  defp contradiction_objects(snapshot) do
    contradiction_ids =
      ContextGraph.contradictions(snapshot)
      |> Enum.flat_map(fn edge -> [edge.from_id, edge.to_id] end)
      |> MapSet.new()

    snapshot
    |> snapshot_context_objects()
    |> Enum.filter(fn object ->
      object_type(object) == "contradiction" or
        MapSet.member?(contradiction_ids, context_id(object))
    end)
    |> Enum.sort_by(&{inserted_at(&1), context_id(&1)})
  end

  defp stale_count(snapshot) do
    snapshot
    |> Map.get(:context_annotations, %{})
    |> Enum.count(fn {_context_id, annotation} ->
      Map.get(annotation, :stale_ancestor) == true or
        Map.get(annotation, "stale_ancestor") == true
    end)
  end

  defp room_objective(snapshot) do
    Map.get(snapshot, :brief) || Map.get(snapshot, "brief") || "No room objective available"
  end

  defp room_status(snapshot) do
    Map.get(snapshot, :status) || Map.get(snapshot, "status") || "idle"
  end

  defp humanize_status(status) when is_binary(status) do
    status
    |> String.replace("_", " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp maybe_add_blocker(blockers, true, blocker), do: blockers ++ [blocker]
  defp maybe_add_blocker(blockers, false, _blocker), do: blockers

  defp maybe_add_message(messages, true, message), do: messages ++ [message]
  defp maybe_add_message(messages, false, _message), do: messages

  defp snapshot_context_objects(%{} = source),
    do: Map.get(source, :context_objects, Map.get(source, "context_objects", []))

  defp object_type(object), do: Map.get(object, :object_type) || Map.get(object, "object_type")
  defp context_id(object), do: Map.get(object, :context_id) || Map.get(object, "context_id")

  defp inserted_at(object) do
    Map.get(object, :inserted_at) || Map.get(object, "inserted_at") ||
      ~U[1970-01-01 00:00:00Z]
  end
end
