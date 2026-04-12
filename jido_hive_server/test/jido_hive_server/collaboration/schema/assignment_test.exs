defmodule JidoHiveServer.Collaboration.Schema.AssignmentTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.Schema.Assignment

  test "builds a canonical assignment with pending status by default" do
    assert {:ok, assignment} =
             Assignment.new(%{
               id: "asg-1",
               room_id: "room-1",
               participant_id: "participant-1",
               payload: %{
                 "objective" => "Analyze the brief.",
                 "phase" => "analysis",
                 "context" => %{"brief" => "Design a substrate."}
               },
               meta: %{"participant_meta" => %{"runtime_kind" => "codex"}}
             })

    assert assignment.id == "asg-1"
    assert assignment.room_id == "room-1"
    assert assignment.participant_id == "participant-1"
    assert assignment.status == "pending"
    assert assignment.payload["phase"] == "analysis"
    assert assignment.meta["participant_meta"]["runtime_kind"] == "codex"
  end

  test "rejects unsupported status values" do
    assert {:error, {:invalid_field, "status"}} =
             Assignment.new(%{
               id: "asg-1",
               room_id: "room-1",
               participant_id: "participant-1",
               status: "offered"
             })
  end
end
