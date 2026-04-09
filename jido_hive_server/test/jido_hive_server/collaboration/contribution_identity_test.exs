defmodule JidoHiveServer.Collaboration.ContributionIdentityTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias JidoHiveServer.Collaboration.RoomServer

  test "rejects conflicting duplicate contribution ids across different assignments" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-duplicate-contribution-id-1",
         snapshot: %{
           room_id: "room-duplicate-contribution-id-1",
           session_id: "session-room-duplicate-contribution-id-1",
           brief: "Detect contribution id conflicts.",
           rules: [],
           status: "running",
           participants: [
             %{
               participant_id: "worker-01",
               participant_role: "worker",
               participant_kind: "runtime",
               authority_level: "advisory",
               target_id: "target-worker-01",
               capability_id: "workspace.exec.session",
               metadata: %{}
             },
             %{
               participant_id: "worker-02",
               participant_role: "worker",
               participant_kind: "runtime",
               authority_level: "advisory",
               target_id: "target-worker-02",
               capability_id: "workspace.exec.session",
               metadata: %{}
             }
           ],
           current_assignment: %{},
           assignments: [],
           context_objects: [],
           contributions: [],
           dispatch_policy_id: "round_robin/v2",
           dispatch_policy_config: %{},
           dispatch_state: %{applied_event_ids: [], completed_slots: 0, total_slots: 2},
           next_context_seq: 1,
           next_assignment_seq: 1,
           next_contribution_seq: 1
         }}
      )

    assert {:ok, _opened} =
             RoomServer.open_assignment(room, %{
               "assignment" => %{
                 "assignment_id" => "asn-1",
                 "room_id" => "room-duplicate-contribution-id-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "worker",
                 "target_id" => "target-worker-01",
                 "capability_id" => "workspace.exec.session",
                 "phase" => "analysis",
                 "objective" => "Analyze.",
                 "contribution_contract" => %{"allowed_contribution_types" => ["reasoning"]},
                 "context_view" => %{
                   "brief" => "Detect contribution id conflicts.",
                   "context_objects" => []
                 },
                 "status" => "running",
                 "opened_at" => DateTime.utc_now()
               }
             })

    assert {:ok, completed} =
             RoomServer.record_contribution(room, %{
               "contribution" => %{
                 "room_id" => "room-duplicate-contribution-id-1",
                 "assignment_id" => "asn-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "worker",
                 "target_id" => "target-worker-01",
                 "capability_id" => "workspace.exec.session",
                 "contribution_id" => "contrib-shared-id",
                 "contribution_type" => "reasoning",
                 "authority_level" => "advisory",
                 "summary" => "First contribution.",
                 "context_objects" => [
                   %{"object_type" => "note", "title" => "first", "body" => "first body"}
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

    assert [%{assignment_id: "asn-1", status: "completed"}] = completed.assignments

    assert {:ok, _opened} =
             RoomServer.open_assignment(room, %{
               "assignment" => %{
                 "assignment_id" => "asn-2",
                 "room_id" => "room-duplicate-contribution-id-1",
                 "participant_id" => "worker-02",
                 "participant_role" => "worker",
                 "target_id" => "target-worker-02",
                 "capability_id" => "workspace.exec.session",
                 "phase" => "analysis",
                 "objective" => "Analyze again.",
                 "contribution_contract" => %{"allowed_contribution_types" => ["reasoning"]},
                 "context_view" => %{
                   "brief" => "Detect contribution id conflicts.",
                   "context_objects" => []
                 },
                 "status" => "running",
                 "opened_at" => DateTime.utc_now()
               }
             })

    assert {:error,
            {:duplicate_contribution_id_conflict,
             %{
               contribution_id: "contrib-shared-id",
               existing_assignment_id: "asn-1",
               incoming_assignment_id: "asn-2",
               existing_participant_id: "worker-01",
               incoming_participant_id: "worker-02"
             }}} =
             RoomServer.record_contribution(room, %{
               "contribution" => %{
                 "room_id" => "room-duplicate-contribution-id-1",
                 "assignment_id" => "asn-2",
                 "participant_id" => "worker-02",
                 "participant_role" => "worker",
                 "target_id" => "target-worker-02",
                 "capability_id" => "workspace.exec.session",
                 "contribution_id" => "contrib-shared-id",
                 "contribution_type" => "reasoning",
                 "authority_level" => "advisory",
                 "summary" => "Second contribution.",
                 "context_objects" => [
                   %{"object_type" => "note", "title" => "second", "body" => "second body"}
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

    assert {:ok, current} = RoomServer.snapshot(room)
    assert length(current.contributions) == 1

    assert Enum.any?(
             current.assignments,
             &(&1.assignment_id == "asn-2" and &1.status == "running")
           )
  end

  test "rejects a second result for the same assignment with a different contribution id" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-duplicate-assignment-result-1",
         snapshot: %{
           room_id: "room-duplicate-assignment-result-1",
           session_id: "session-room-duplicate-assignment-result-1",
           brief: "Detect duplicate assignment result conflicts.",
           rules: [],
           status: "running",
           participants: [
             %{
               participant_id: "worker-01",
               participant_role: "worker",
               participant_kind: "runtime",
               authority_level: "advisory",
               target_id: "target-worker-01",
               capability_id: "workspace.exec.session",
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

    assert {:ok, _opened} =
             RoomServer.open_assignment(room, %{
               "assignment" => %{
                 "assignment_id" => "asn-1",
                 "room_id" => "room-duplicate-assignment-result-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "worker",
                 "target_id" => "target-worker-01",
                 "capability_id" => "workspace.exec.session",
                 "phase" => "analysis",
                 "objective" => "Analyze.",
                 "contribution_contract" => %{"allowed_contribution_types" => ["reasoning"]},
                 "context_view" => %{
                   "brief" => "Detect duplicate assignment result conflicts.",
                   "context_objects" => []
                 },
                 "status" => "running",
                 "opened_at" => DateTime.utc_now()
               }
             })

    assert {:ok, completed} =
             RoomServer.record_contribution(room, %{
               "contribution" => %{
                 "room_id" => "room-duplicate-assignment-result-1",
                 "assignment_id" => "asn-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "worker",
                 "target_id" => "target-worker-01",
                 "capability_id" => "workspace.exec.session",
                 "contribution_id" => "contrib-first-id",
                 "contribution_type" => "reasoning",
                 "authority_level" => "advisory",
                 "summary" => "First contribution.",
                 "context_objects" => [
                   %{"object_type" => "note", "title" => "first", "body" => "first body"}
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

    assert [%{assignment_id: "asn-1", status: "completed"}] = completed.assignments

    assert {:error,
            {:duplicate_assignment_result_conflict,
             %{
               assignment_id: "asn-1",
               participant_id: "worker-01",
               existing_contribution_id: "contrib-first-id",
               incoming_contribution_id: "contrib-second-id"
             }}} =
             RoomServer.record_contribution(room, %{
               "contribution" => %{
                 "room_id" => "room-duplicate-assignment-result-1",
                 "assignment_id" => "asn-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "worker",
                 "target_id" => "target-worker-01",
                 "capability_id" => "workspace.exec.session",
                 "contribution_id" => "contrib-second-id",
                 "contribution_type" => "reasoning",
                 "authority_level" => "advisory",
                 "summary" => "Second contribution.",
                 "context_objects" => [
                   %{"object_type" => "note", "title" => "second", "body" => "second body"}
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

    assert {:ok, current} = RoomServer.snapshot(room)
    assert length(current.contributions) == 1
    assert [%{assignment_id: "asn-1", status: "completed"}] = current.assignments
  end
end
