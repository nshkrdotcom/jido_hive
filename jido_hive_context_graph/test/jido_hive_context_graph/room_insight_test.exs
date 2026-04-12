defmodule JidoHiveContextGraph.RoomInsightTest do
  use ExUnit.Case, async: true

  alias JidoHiveContextGraph.RoomInsight

  test "builds a control-plane digest with readable blockers and focus queue" do
    digest = RoomInsight.control_plane(snapshot())

    assert digest.objective == "Stabilize the Redis auth path"
    assert digest.stage == "Resolve contradictions"
    assert digest.next_action =~ "binding resolution"
    assert digest.reason == "Open contradictions remain"
    assert digest.publish_ready == false

    assert digest.focus_queue == [
             %{
               kind: "contradiction",
               context_id: "ctx-2",
               title: "Datadog says Redis is fine",
               why: "Contradiction requires operator arbitration",
               action: "Open conflict resolution"
             },
             %{
               kind: "duplicate_cluster",
               context_id: "ctx-1",
               title: "Redis timeout",
               why: "1 duplicate is collapsed under the canonical entry",
               action: "Review the canonical entry before accepting or publishing"
             }
           ]

    assert digest.graph_counts == %{
             contradictions: 1,
             decisions: 1,
             duplicates: 1,
             stale: 1,
             total: 3
           }
  end

  test "builds a structured provenance trace with operator actions" do
    assert {:ok, trace} = RoomInsight.provenance_trace(provenance_snapshot(), "ctx-3")

    assert trace.context_id == "ctx-3"
    assert trace.title == "Rollback registry deploy"
    assert trace.graph == %{incoming: 0, outgoing: 1}
    assert trace.flags == %{binding: false, conflict: false, duplicate_count: 0, stale: false}

    assert trace.recommended_actions == [
             %{label: "Inspect provenance", shortcut: "Ctrl+E"},
             %{label: "Accept selected object", shortcut: "Ctrl+A"},
             %{label: "Review publication plan", shortcut: "Ctrl+P"}
           ]

    assert trace.trace == [
             %{
               depth: 0,
               via: nil,
               context_id: "ctx-3",
               object_type: "decision",
               title: "Rollback registry deploy",
               cycle: false
             },
             %{
               depth: 1,
               via: "references",
               context_id: "ctx-1",
               object_type: "belief",
               title: "Redis timeout",
               cycle: false
             },
             %{
               depth: 2,
               via: "derives_from",
               context_id: "ctx-4",
               object_type: "evidence",
               title: "PagerDuty alerts",
               cycle: false
             }
           ]
  end

  test "infers duplicate-cluster focus items from canonical objects when the workflow contract is sparse" do
    digest =
      RoomInsight.control_plane(%{
        "name" => "Stabilize the Redis auth path",
        "status" => "running",
        "workflow_summary" => %{
          "objective" => "Stabilize the Redis auth path",
          "stage" => "Steer active work",
          "next_action" => "Review the graph",
          "publish_ready" => false,
          "publish_blockers" => ["No decision has been recorded"],
          "graph_counts" => %{"duplicates" => 1, "total" => 2},
          "focus_candidates" => []
        },
        "context_objects" => [
          %{
            "context_id" => "ctx-1",
            "object_type" => "belief",
            "title" => "Redis timeout",
            "derived" => %{
              "duplicate_status" => "canonical",
              "duplicate_size" => 2,
              "duplicate_context_ids" => ["ctx-1", "ctx-2"],
              "canonical_context_id" => "ctx-1"
            }
          },
          %{
            "context_id" => "ctx-2",
            "object_type" => "belief",
            "title" => "Redis timeout",
            "derived" => %{
              "duplicate_status" => "duplicate",
              "duplicate_size" => 2,
              "duplicate_context_ids" => ["ctx-1", "ctx-2"],
              "canonical_context_id" => "ctx-1"
            }
          }
        ]
      })

    assert digest.focus_queue == [
             %{
               kind: "duplicate_cluster",
               context_id: "ctx-1",
               title: "Redis timeout",
               why: "1 duplicate is collapsed under the canonical entry",
               action: "Review the canonical entry before accepting or publishing"
             }
           ]
  end

  defp snapshot do
    %{
      "name" => "Stabilize the Redis auth path",
      "status" => "running",
      "workflow_summary" => %{
        "objective" => "Stabilize the Redis auth path",
        "stage" => "Resolve contradictions",
        "next_action" => "Review ctx-2 and submit a binding resolution",
        "blockers" => [%{"kind" => "contradiction", "count" => 1}],
        "publish_ready" => false,
        "publish_blockers" => ["Open contradictions remain"],
        "graph_counts" => %{
          "decisions" => 1,
          "questions" => 0,
          "contradictions" => 1,
          "duplicates" => 1,
          "stale" => 1,
          "total" => 3
        },
        "focus_candidates" => [
          %{"kind" => "contradiction", "context_id" => "ctx-2"},
          %{"kind" => "duplicate_cluster", "context_id" => "ctx-1", "duplicate_count" => 1}
        ]
      },
      "context_objects" => [
        %{
          "context_id" => "ctx-1",
          "object_type" => "belief",
          "title" => "Redis timeout",
          "derived" => %{
            "stale_ancestor" => true,
            "duplicate_status" => "canonical",
            "duplicate_size" => 2,
            "duplicate_context_ids" => ["ctx-1", "ctx-4"],
            "canonical_context_id" => "ctx-1"
          }
        },
        %{
          "context_id" => "ctx-2",
          "object_type" => "contradiction",
          "title" => "Datadog says Redis is fine"
        },
        %{
          "context_id" => "ctx-3",
          "object_type" => "decision",
          "title" => "Rollback registry deploy"
        },
        %{
          "context_id" => "ctx-4",
          "object_type" => "belief",
          "title" => "Redis timeout",
          "derived" => %{
            "duplicate_status" => "duplicate",
            "duplicate_size" => 2,
            "duplicate_context_ids" => ["ctx-1", "ctx-4"],
            "canonical_context_id" => "ctx-1"
          }
        }
      ]
    }
  end

  defp provenance_snapshot do
    %{
      "context_objects" => [
        %{
          "context_id" => "ctx-1",
          "object_type" => "belief",
          "title" => "Redis timeout",
          "relations" => [%{"relation" => "derives_from", "target_id" => "ctx-4"}]
        },
        %{
          "context_id" => "ctx-3",
          "object_type" => "decision",
          "title" => "Rollback registry deploy",
          "relations" => [%{"relation" => "references", "target_id" => "ctx-1"}]
        },
        %{
          "context_id" => "ctx-4",
          "object_type" => "evidence",
          "title" => "PagerDuty alerts",
          "relations" => []
        }
      ]
    }
  end
end
