defmodule JidoHiveContextGraph.WorkflowSummaryTest do
  use ExUnit.Case, async: true

  alias JidoHiveContextGraph.WorkflowSummary

  test "treats waiting rooms with no decisions as not yet started" do
    summary =
      WorkflowSummary.build(%{
        "name" => "Decide on the rollout plan",
        "status" => "waiting",
        "context_objects" => []
      })

    assert summary.stage == "Start the room"
    assert summary.next_action == "Start a room run or send the first steering message"
    refute summary.publish_ready
    assert summary.publish_blockers == ["No decision has been recorded"]
  end

  test "derives publish readiness from graph state instead of room status aliases" do
    summary =
      WorkflowSummary.build(%{
        "name" => "Decide on the rollout plan",
        "status" => "completed",
        "context_objects" => [
          %{
            "context_id" => "ctx-1",
            "object_type" => "decision",
            "title" => "Ship the cutover"
          }
        ]
      })

    assert summary.stage == "Ready to publish"

    assert summary.next_action ==
             "Review the publication plan and submit to the selected channels"

    assert summary.publish_ready
    assert summary.publish_blockers == []
  end
end
