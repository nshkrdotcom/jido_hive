defmodule JidoHiveServer.Collaboration.RoomServerTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias JidoHiveServer.Collaboration.RoomServer
  alias JidoHiveServer.Persistence

  test "persists round-robin turns across proposal, critique, and resolution stages" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-state-1",
         session_id: "session-room-state-1",
         brief: "Design a client-server collaboration protocol for AI agents.",
         rules: ["Every objection must target a claim."],
         participants: [
           %{
             participant_id: "worker-01",
             role: "worker",
             target_id: "target-worker-01",
             capability_id: "codex.exec.session"
           },
           %{
             participant_id: "worker-02",
             role: "worker",
             target_id: "target-worker-02",
             capability_id: "codex.exec.session"
           }
         ]}
      )

    assert {:ok, initial} = RoomServer.snapshot(room)
    assert initial.execution_plan.participant_count == 2
    assert initial.execution_plan.planned_turn_count == 6

    assert {:ok, opened_1} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-worker-01-proposal",
               "plan_slot_index" => 0,
               "participant_id" => "worker-01",
               "participant_role" => "proposer",
               "target_id" => "target-worker-01",
               "capability_id" => "codex.exec.session",
               "phase" => "proposal",
               "objective" => "Produce proposal pass one.",
               "round" => 1,
               "session" => %{"provider" => "claude", "workspace_root" => "/tmp/hive"},
               "collaboration_envelope" => %{"turn" => %{"phase" => "proposal"}}
             })

    assert opened_1.phase == "proposal"
    assert opened_1.execution_plan.round_robin_index == 1

    assert {:ok, after_proposal_1} =
             RoomServer.apply_result(room, proposal_result("job-worker-01-proposal"))

    assert after_proposal_1.status == "in_progress"
    assert after_proposal_1.phase == "proposal"
    assert after_proposal_1.execution_plan.completed_turn_count == 1

    assert {:ok, _opened_2} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-worker-02-proposal",
               "plan_slot_index" => 1,
               "participant_id" => "worker-02",
               "participant_role" => "proposer",
               "target_id" => "target-worker-02",
               "capability_id" => "codex.exec.session",
               "phase" => "proposal",
               "objective" => "Produce proposal pass two.",
               "round" => 2,
               "session" => %{"provider" => "claude", "workspace_root" => "/tmp/hive"},
               "collaboration_envelope" => %{"turn" => %{"phase" => "proposal"}}
             })

    assert {:ok, after_proposal_2} =
             RoomServer.apply_result(room, proposal_result("job-worker-02-proposal"))

    assert after_proposal_2.phase == "critique"
    assert after_proposal_2.execution_plan.completed_turn_count == 2

    assert {:ok, _opened_3} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-worker-01-critique",
               "plan_slot_index" => 0,
               "participant_id" => "worker-01",
               "participant_role" => "critic",
               "target_id" => "target-worker-01",
               "capability_id" => "codex.exec.session",
               "phase" => "critique",
               "objective" => "Critique pass one.",
               "round" => 3,
               "session" => %{"provider" => "claude", "workspace_root" => "/tmp/hive"},
               "collaboration_envelope" => %{"turn" => %{"phase" => "critique"}}
             })

    assert {:ok, after_critique_1} =
             RoomServer.apply_result(room, critique_result("job-worker-01-critique", "claim:1"))

    assert after_critique_1.status == "in_progress"
    assert after_critique_1.phase == "critique"
    assert Enum.count(after_critique_1.disputes, &(&1.status == :open)) == 1

    assert {:ok, _opened_4} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-worker-02-critique",
               "plan_slot_index" => 1,
               "participant_id" => "worker-02",
               "participant_role" => "critic",
               "target_id" => "target-worker-02",
               "capability_id" => "codex.exec.session",
               "phase" => "critique",
               "objective" => "Critique pass two.",
               "round" => 4,
               "session" => %{"provider" => "claude", "workspace_root" => "/tmp/hive"},
               "collaboration_envelope" => %{"turn" => %{"phase" => "critique"}}
             })

    assert {:ok, after_critique_2} =
             RoomServer.apply_result(room, critique_result("job-worker-02-critique", "claim:3"))

    assert after_critique_2.phase == "resolution"
    assert Enum.count(after_critique_2.disputes, &(&1.status == :open)) == 2

    assert {:ok, _opened_5} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-worker-01-resolution",
               "plan_slot_index" => 0,
               "participant_id" => "worker-01",
               "participant_role" => "resolver",
               "target_id" => "target-worker-01",
               "capability_id" => "codex.exec.session",
               "phase" => "resolution",
               "objective" => "Resolution pass one.",
               "round" => 5,
               "session" => %{"provider" => "claude", "workspace_root" => "/tmp/hive"},
               "collaboration_envelope" => %{"turn" => %{"phase" => "resolution"}}
             })

    assert {:ok, after_resolution_1} =
             RoomServer.apply_result(
               room,
               resolution_result("job-worker-01-resolution", "dispute:1")
             )

    assert after_resolution_1.status == "in_progress"
    assert after_resolution_1.phase == "resolution"
    assert Enum.count(after_resolution_1.disputes, &(&1.status == :resolved)) == 1

    assert {:ok, _opened_6} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-worker-02-resolution",
               "plan_slot_index" => 1,
               "participant_id" => "worker-02",
               "participant_role" => "resolver",
               "target_id" => "target-worker-02",
               "capability_id" => "codex.exec.session",
               "phase" => "resolution",
               "objective" => "Resolution pass two.",
               "round" => 6,
               "session" => %{"provider" => "claude", "workspace_root" => "/tmp/hive"},
               "collaboration_envelope" => %{"turn" => %{"phase" => "resolution"}}
             })

    assert {:ok, resolved} =
             RoomServer.apply_result(
               room,
               resolution_result("job-worker-02-resolution", "dispute:2")
             )

    assert resolved.status == "publication_ready"
    assert resolved.phase == "publication_ready"
    assert resolved.execution_plan.completed_turn_count == 6
    assert Enum.all?(resolved.disputes, &(&1.status == :resolved))

    assert Enum.map(resolved.turns, & &1.phase) == [
             "proposal",
             "proposal",
             "critique",
             "critique",
             "resolution",
             "resolution"
           ]

    assert {:ok, persisted} = Persistence.fetch_room_snapshot("room-state-1")
    assert persisted.status == "publication_ready"
    assert length(persisted.turns) == 6
  end

  test "retains boundary_session_id and reopen metadata in room state for later turns" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-boundary-state-1",
         session_id: "session-room-boundary-state-1",
         brief: "Retain one bridge-backed boundary across turns.",
         rules: ["Reuse the retained boundary instead of reallocating blindly."],
         participants: [
           %{
             participant_id: "worker-01",
             role: "worker",
             target_id: "target-worker-01",
             capability_id: "codex.exec.session"
           }
         ]}
      )

    assert {:ok, opened} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-worker-01-boundary",
               "plan_slot_index" => 0,
               "participant_id" => "worker-01",
               "participant_role" => "proposer",
               "target_id" => "target-worker-01",
               "capability_id" => "codex.exec.session",
               "phase" => "proposal",
               "objective" => "Use the retained boundary-backed session.",
               "round" => 1,
               "session" => %{
                 "provider" => "codex",
                 "boundary" => %{
                   "descriptor" => %{
                     "descriptor_version" => 1,
                     "boundary_session_id" => "bnd-room-state-1"
                   },
                   "reopen_request" => %{
                     "boundary_session_id" => "bnd-room-state-1",
                     "backend_kind" => "microvm"
                   }
                 }
               },
               "collaboration_envelope" => %{"turn" => %{"phase" => "proposal"}}
             })

    assert opened.boundary_sessions["target-worker-01"]["boundary_session_id"] ==
             "bnd-room-state-1"

    assert opened.boundary_sessions["target-worker-01"]["reopen_request"]["backend_kind"] ==
             "microvm"

    assert {:ok, persisted} = Persistence.fetch_room_snapshot("room-boundary-state-1")

    assert persisted.boundary_sessions["target-worker-01"]["boundary_session_id"] ==
             "bnd-room-state-1"
  end

  defp proposal_result(job_id) do
    %{
      "job_id" => job_id,
      "participant_id" => "worker",
      "participant_role" => "proposer",
      "status" => "completed",
      "summary" => "proposal pass added shared packet structure",
      "actions" => [
        %{
          "op" => "CLAIM",
          "title" => "Shared packet",
          "body" => "The server should own a shared packet of instructions, context, and refs."
        },
        %{
          "op" => "EVIDENCE",
          "title" => "Packet lineage",
          "body" => "Each turn should carry the prior structured actions and tool traces forward."
        },
        %{
          "op" => "PUBLISH",
          "title" => "Publish the reviewed protocol",
          "body" =>
            "Prepare both GitHub and Notion publication payloads from the shared room state."
        }
      ],
      "tool_events" => [
        %{"event_type" => "tool_call", "payload" => %{"tool_name" => "context.read"}}
      ],
      "events" => [%{"type" => "assistant_delta"}],
      "approvals" => [],
      "artifacts" => [],
      "execution" => %{"status" => "completed", "provider" => "claude", "text" => "{}"}
    }
  end

  defp critique_result(job_id, entry_ref) do
    %{
      "job_id" => job_id,
      "participant_id" => "worker",
      "participant_role" => "critic",
      "status" => "completed",
      "summary" => "critique pass opened one objection",
      "actions" => [
        %{
          "op" => "OBJECT",
          "title" => "Conflict handling is underspecified",
          "body" => "The packet flow does not define how contradictory tool output is preserved.",
          "targets" => [%{"entry_ref" => entry_ref}],
          "severity" => "high"
        }
      ],
      "tool_events" => [
        %{"event_type" => "tool_call", "payload" => %{"tool_name" => "critique.scan"}}
      ],
      "events" => [%{"type" => "assistant_delta"}],
      "approvals" => [],
      "artifacts" => [],
      "execution" => %{"status" => "completed", "provider" => "claude", "text" => "{}"}
    }
  end

  defp resolution_result(job_id, dispute_id) do
    %{
      "job_id" => job_id,
      "participant_id" => "worker",
      "participant_role" => "resolver",
      "status" => "completed",
      "summary" => "resolution pass resolved #{dispute_id}",
      "actions" => [
        %{
          "op" => "REVISE",
          "title" => "Contradiction ledger",
          "body" => "Keep a contradiction ledger in the shared envelope.",
          "targets" => [%{"dispute_id" => dispute_id}]
        },
        %{
          "op" => "DECIDE",
          "title" => "Ready to publish",
          "body" => "The room is publishable after the contradiction ledger revision.",
          "targets" => [%{"dispute_id" => dispute_id}]
        }
      ],
      "tool_events" => [
        %{"event_type" => "tool_call", "payload" => %{"tool_name" => "revision.apply"}}
      ],
      "events" => [%{"type" => "assistant_delta"}],
      "approvals" => [],
      "artifacts" => [],
      "execution" => %{"status" => "completed", "provider" => "claude", "text" => "{}"}
    }
  end
end
