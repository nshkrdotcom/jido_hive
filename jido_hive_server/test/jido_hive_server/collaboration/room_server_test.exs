defmodule JidoHiveServer.Collaboration.RoomServerTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias JidoHiveServer.Collaboration.RoomServer
  alias JidoHiveServer.Persistence

  test "persists assignments and contributions for a room" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-state-1",
         snapshot: %{
           room_id: "room-state-1",
           session_id: "session-room-state-1",
           brief: "Design a participation substrate.",
           rules: ["Return structured contributions only."],
           status: "idle",
           participants: [
             %{
               participant_id: "worker-01",
               participant_role: "analyst",
               participant_kind: "runtime",
               authority_level: "advisory",
               target_id: "target-worker-01",
               capability_id: "codex.exec.session",
               metadata: %{}
             }
           ],
           current_assignment: %{},
           assignments: [],
           context_objects: [],
           contributions: [],
           dispatch_policy_id: "round_robin/v2",
           dispatch_policy_config: %{},
           dispatch_state: %{applied_event_ids: [], completed_slots: 0, total_slots: 1},
           next_context_seq: 1,
           next_assignment_seq: 1,
           next_contribution_seq: 1
         }}
      )

    assert {:ok, opened} =
             RoomServer.open_assignment(room, %{
               "assignment" => %{
                 "assignment_id" => "asn-1",
                 "room_id" => "room-state-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "analyst",
                 "target_id" => "target-worker-01",
                 "capability_id" => "codex.exec.session",
                 "phase" => "analysis",
                 "objective" => "Analyze the brief.",
                 "contribution_contract" => %{"allowed_contribution_types" => ["reasoning"]},
                 "context_view" => %{"brief" => "Design a substrate.", "context_objects" => []},
                 "status" => "running",
                 "opened_at" => DateTime.utc_now()
               }
             })

    assert opened.current_assignment.assignment_id == "asn-1"

    assert {:ok, completed} =
             RoomServer.record_contribution(room, %{
               "contribution" => %{
                 "room_id" => "room-state-1",
                 "assignment_id" => "asn-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "analyst",
                 "target_id" => "target-worker-01",
                 "capability_id" => "codex.exec.session",
                 "contribution_type" => "reasoning",
                 "authority_level" => "advisory",
                 "summary" => "Added a belief.",
                 "consumed_context_ids" => [],
                 "context_objects" => [
                   %{
                     "object_type" => "belief",
                     "title" => "Shared state",
                     "body" => "Server-owned state."
                   }
                 ],
                 "artifacts" => [],
                 "events" => [],
                 "tool_events" => [],
                 "approvals" => [],
                 "execution" => %{"status" => "completed"},
                 "status" => "completed",
                 "schema_version" => "jido_hive/contribution.submit.v1"
               }
             })

    assert completed.status == "publication_ready"
    assert [%{assignment_id: "asn-1", status: "completed"}] = completed.assignments
    assert [%{context_id: "ctx-1"}] = completed.context_objects

    assert {:ok, persisted} = Persistence.fetch_room_snapshot("room-state-1")
    assert persisted.status == "publication_ready"
    assert length(persisted.assignments) == 1
    assert length(persisted.contributions) == 1
  end
end
