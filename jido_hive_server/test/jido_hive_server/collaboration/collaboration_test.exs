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
               dispatch_policy_id: "round_robin/v2",
               participants: [
                 %{
                   participant_id: "worker-01",
                   participant_role: "analyst",
                   participant_kind: "runtime",
                   target_id: "target-worker-01",
                   capability_id: "codex.exec.session"
                 }
               ]
             })

    assert room.status == "idle"
    assert room.dispatch_state.total_slots == 3

    assert {:ok, _updated} =
             RoomServer.open_assignment(RoomServer.via("room-reuse-1"), %{
               "assignment" => %{
                 "assignment_id" => "asn-reuse-1",
                 "room_id" => "room-reuse-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "analyst",
                 "target_id" => "target-worker-01",
                 "capability_id" => "codex.exec.session",
                 "phase" => "analysis",
                 "objective" => "Analyze the first draft.",
                 "contribution_contract" => %{"allowed_contribution_types" => ["reasoning"]},
                 "context_view" => %{"brief" => "Original brief", "context_objects" => []},
                 "status" => "running",
                 "opened_at" => DateTime.utc_now()
               }
             })

    assert {:ok, reused} =
             Collaboration.create_room(%{
               room_id: "room-reuse-1",
               brief: "Replacement brief",
               rules: ["rule-two"],
               dispatch_policy_id: "round_robin/v2",
               participants: [
                 %{
                   participant_id: "worker-01",
                   participant_role: "analyst",
                   participant_kind: "runtime",
                   target_id: "target-worker-01",
                   capability_id: "codex.exec.session"
                 }
               ]
             })

    assert reused.brief == "Replacement brief"
    assert reused.rules == ["rule-two"]
    assert reused.status == "idle"
    assert reused.assignments == []
    assert reused.context_objects == []
    assert reused.current_assignment == %{}
  end
end
