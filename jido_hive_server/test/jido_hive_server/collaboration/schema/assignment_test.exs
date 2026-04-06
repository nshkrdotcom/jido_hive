defmodule JidoHiveServer.Collaboration.Schema.AssignmentTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.Schema.Assignment

  test "builds an assignment with normalized defaults" do
    assert {:ok, assignment} =
             Assignment.new(%{
               assignment_id: "asn-1",
               room_id: "room-1",
               participant_id: "worker-01",
               participant_role: "analyst",
               target_id: "target-worker-01",
               capability_id: "codex.exec.session",
               phase: "analysis",
               objective: "Analyze the brief.",
               contribution_contract: %{"allowed_contribution_types" => ["reasoning"]},
               context_view: %{"brief" => "Design a substrate.", "context_objects" => []}
             })

    assert assignment.status == "running"
    assert assignment.phase == "analysis"
    assert assignment.participant_role == "analyst"
  end
end
