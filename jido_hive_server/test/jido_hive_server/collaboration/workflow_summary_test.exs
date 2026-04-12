defmodule JidoHiveServer.Collaboration.WorkflowSummaryTest do
  use ExUnit.Case, async: true

  alias JidoHiveContextGraph.WorkflowSummary
  alias JidoHiveServer.Collaboration.SnapshotProjection

  test "builds a deterministic room workflow summary with contradiction and duplicate pressure" do
    snapshot =
      %{
        room_id: "room-summary-1",
        brief: "Stabilize the Redis auth path",
        status: "running",
        dispatch_state: %{completed_slots: 1, total_slots: 3},
        context_objects: [
          context_object("ctx-1", "belief", "Redis timeout", "Auth requests are timing out.",
            inserted_at: ~U[2026-04-09 10:00:00Z]
          ),
          context_object("ctx-2", "belief", "Redis timeout", "Auth requests are timing out.",
            inserted_at: ~U[2026-04-09 10:01:00Z]
          ),
          context_object("ctx-3", "question", "Need the failing shard", "Which shard is failing?",
            inserted_at: ~U[2026-04-09 10:02:00Z]
          ),
          context_object(
            "ctx-4",
            "note",
            "Counterpoint",
            "Datadog says Redis is healthy.",
            inserted_at: ~U[2026-04-09 10:03:00Z],
            relations: [%{relation: "contradicts", target_id: "ctx-1"}]
          )
        ],
        contributions: [],
        assignments: [],
        current_assignment: %{},
        participants: [],
        context_config: %{participant_scopes: %{}},
        dispatch_policy_id: "round_robin/v2",
        dispatch_policy_config: %{},
        next_context_seq: 5,
        next_assignment_seq: 1,
        next_contribution_seq: 1
      }
      |> SnapshotProjection.project()

    summary = WorkflowSummary.build(snapshot)

    assert summary.objective == "Stabilize the Redis auth path"
    assert summary.stage == "Resolve contradictions"
    assert summary.next_action =~ "binding resolution"

    assert summary.blockers == [
             %{kind: "contradiction", count: 2},
             %{kind: "open_question", count: 1},
             %{kind: "missing_decision", count: 1}
           ]

    assert summary.publish_ready == false
    assert "Open contradictions remain" in summary.publish_blockers

    assert summary.graph_counts == %{
             total: 3,
             decisions: 0,
             questions: 1,
             contradictions: 2,
             duplicate_groups: 1,
             duplicates: 1,
             stale: 0
           }

    assert Enum.any?(
             summary.focus_candidates,
             &(&1 == %{kind: "duplicate_cluster", context_id: "ctx-1", duplicate_count: 1})
           )

    assert Enum.any?(summary.focus_candidates, &(&1 == %{kind: "question", context_id: "ctx-3"}))
  end

  test "marks publication-ready rooms as ready to publish" do
    summary =
      %{
        room_id: "room-summary-2",
        brief: "Ship the release note",
        status: "publication_ready",
        context_objects: [
          context_object("ctx-1", "decision", "Ship it", "Approve the release note.")
        ]
      }
      |> SnapshotProjection.project()
      |> WorkflowSummary.build()

    assert summary.stage == "Ready to publish"
    assert summary.publish_ready == true
    assert summary.publish_blockers == []
    assert summary.next_action =~ "publication plan"
  end

  defp context_object(context_id, object_type, title, body, attrs \\ []) do
    %{
      context_id: context_id,
      object_type: object_type,
      title: title,
      body: body,
      data: %{},
      relations: Keyword.get(attrs, :relations, []),
      inserted_at: Keyword.get(attrs, :inserted_at, ~U[2026-04-09 10:00:00Z])
    }
  end
end
