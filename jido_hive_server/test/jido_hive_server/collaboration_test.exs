defmodule JidoHiveServer.CollaborationTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias JidoHiveServer.Collaboration
  alias JidoHiveServer.Collaboration.RoomServer

  test "create_room replaces any live room state for the same room id" do
    assert {:ok, room} =
             Collaboration.create_room(%{
               room_id: "room-reuse-1",
               brief: "Original brief",
               rules: ["rule-one"],
               participants: [
                 %{
                   participant_id: "architect",
                   role: "architect",
                   target_id: "target-architect",
                   capability_id: "codex.exec.session"
                 }
               ]
             })

    assert room.status == "idle"

    assert {:ok, _updated} =
             RoomServer.open_turn(RoomServer.via("room-reuse-1"), %{
               "job_id" => "job-reuse-1",
               "participant_id" => "architect",
               "participant_role" => "architect",
               "target_id" => "target-architect",
               "capability_id" => "codex.exec.session",
               "phase" => "proposal",
               "objective" => "Draft the first proposal.",
               "round" => 1,
               "session" => %{"provider" => "claude", "workspace_root" => "/tmp/reuse"},
               "collaboration_envelope" => %{"turn" => %{"phase" => "proposal"}}
             })

    assert {:ok, reused} =
             Collaboration.create_room(%{
               room_id: "room-reuse-1",
               brief: "Replacement brief",
               rules: ["rule-two"],
               participants: []
             })

    assert reused.brief == "Replacement brief"
    assert reused.rules == ["rule-two"]
    assert reused.status == "idle"
    assert reused.phase == "idle"
    assert reused.turns == []
    assert reused.context_entries == []
    assert reused.disputes == []
    assert reused.current_turn == %{}
  end
end
