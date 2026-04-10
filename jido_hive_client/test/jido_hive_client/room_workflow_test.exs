defmodule JidoHiveClient.RoomWorkflowTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.RoomWorkflow

  test "normalizes the server workflow summary contract" do
    summary =
      RoomWorkflow.summary(%{
        "room_id" => "room-1",
        "brief" => "Stabilize the Redis auth path",
        "status" => "running",
        "workflow_summary" => %{
          "objective" => "Stabilize the Redis auth path",
          "stage" => "Resolve contradictions",
          "next_action" => "Review ctx-4 and submit a binding resolution",
          "blockers" => [%{"kind" => "contradiction", "count" => 2}],
          "publish_ready" => false,
          "publish_blockers" => ["Open contradictions remain"],
          "graph_counts" => %{"duplicates" => 1, "contradictions" => 2},
          "focus_candidates" => [%{"kind" => "contradiction", "context_id" => "ctx-4"}]
        }
      })

    assert summary == %{
             objective: "Stabilize the Redis auth path",
             stage: "Resolve contradictions",
             next_action: "Review ctx-4 and submit a binding resolution",
             blockers: [%{kind: "contradiction", count: 2}],
             publish_ready: false,
             publish_blockers: ["Open contradictions remain"],
             graph_counts: %{duplicates: 1, contradictions: 2},
             focus_candidates: [%{kind: "contradiction", context_id: "ctx-4"}]
           }
  end

  test "provides a conservative fallback when workflow summary is missing" do
    summary =
      RoomWorkflow.summary(%{
        "room_id" => "room-1",
        "brief" => "Exercise fallback behavior",
        "status" => "running",
        "context_objects" => [%{"context_id" => "ctx-1"}]
      })

    assert summary.objective == "Exercise fallback behavior"
    assert summary.stage == "Running"
    assert summary.next_action == "Refresh room data"
    assert summary.graph_counts.total == 1
    assert summary.publish_ready == false
  end

  test "builds an inspect payload from consolidated sync data" do
    inspect_payload =
      RoomWorkflow.inspect_sync(%{
        room_snapshot: %{
          "room_id" => "room-1",
          "status" => "publication_ready",
          "workflow_summary" => %{
            "objective" => "Ship the room output",
            "stage" => "Ready to publish",
            "next_action" => "Review the publication plan and submit to the selected channels",
            "blockers" => [],
            "publish_ready" => true,
            "publish_blockers" => [],
            "graph_counts" => %{"decisions" => 1},
            "focus_candidates" => []
          }
        },
        entries: [%{"event_id" => "evt-1"}],
        context_objects: [%{"context_id" => "ctx-1"}],
        operations: [%{"operation_id" => "room_run-1"}],
        next_cursor: "evt-1"
      })

    assert inspect_payload.room_id == "room-1"
    assert inspect_payload.status == "publication_ready"
    assert inspect_payload.workflow_summary.stage == "Ready to publish"
    assert inspect_payload.entries == [%{"event_id" => "evt-1"}]
    assert inspect_payload.context_objects == [%{"context_id" => "ctx-1"}]
    assert inspect_payload.operations == [%{"operation_id" => "room_run-1"}]
    assert inspect_payload.next_cursor == "evt-1"
  end
end
