defmodule JidoHiveServer.Collaboration.RoomServerTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias JidoHiveServer.Collaboration.RoomServer
  alias JidoHiveServer.Persistence

  test "persists turns, opens disputes from objections, and resolves them into a publishable room" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-state-1",
         session_id: "session-room-state-1",
         brief: "Design a client-server collaboration protocol for AI agents.",
         rules: ["Every objection must target a claim."],
         participants: [
           %{
             participant_id: "architect",
             role: "architect",
             target_id: "target-architect",
             capability_id: "codex.exec.session"
           },
           %{
             participant_id: "skeptic",
             role: "skeptic",
             target_id: "target-skeptic",
             capability_id: "codex.exec.session"
           }
         ]}
      )

    assert {:ok, opened} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-architect-1",
               "participant_id" => "architect",
               "participant_role" => "architect",
               "target_id" => "target-architect",
               "capability_id" => "codex.exec.session",
               "phase" => "proposal",
               "objective" => "Produce the first proposal.",
               "round" => 1,
               "session" => %{"provider" => "claude", "workspace_root" => "/tmp/hive"},
               "collaboration_envelope" => %{"turn" => %{"phase" => "proposal"}}
             })

    assert opened.current_turn.phase == "proposal"

    assert {:ok, after_architect} = RoomServer.apply_result(room, architect_result())

    assert Enum.map(after_architect.context_entries, & &1.entry_type) == [
             "claim",
             "evidence",
             "publish_request"
           ]

    assert after_architect.status == "in_review"
    assert after_architect.phase == "critique"

    assert {:ok, _opened_again} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-skeptic-1",
               "participant_id" => "skeptic",
               "participant_role" => "skeptic",
               "target_id" => "target-skeptic",
               "capability_id" => "codex.exec.session",
               "phase" => "critique",
               "objective" => "Critique the proposal.",
               "round" => 2,
               "session" => %{"provider" => "claude", "workspace_root" => "/tmp/hive"},
               "collaboration_envelope" => %{"turn" => %{"phase" => "critique"}}
             })

    assert {:ok, after_skeptic} = RoomServer.apply_result(room, skeptic_result())
    assert after_skeptic.status == "needs_resolution"
    assert Enum.any?(after_skeptic.disputes, &(&1.status == :open))

    assert {:ok, _opened_resolution} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-architect-2",
               "participant_id" => "architect",
               "participant_role" => "architect",
               "target_id" => "target-architect",
               "capability_id" => "codex.exec.session",
               "phase" => "resolution",
               "objective" => "Resolve the open dispute.",
               "round" => 3,
               "session" => %{"provider" => "claude", "workspace_root" => "/tmp/hive"},
               "collaboration_envelope" => %{"turn" => %{"phase" => "resolution"}}
             })

    assert {:ok, resolved} = RoomServer.apply_result(room, resolver_result())

    assert Enum.map(resolved.context_entries, & &1.entry_type) == [
             "claim",
             "evidence",
             "publish_request",
             "objection",
             "revision",
             "decision"
           ]

    assert Enum.all?(resolved.disputes, &(&1.status == :resolved))
    assert resolved.status == "publication_ready"
    assert resolved.phase == "publication_ready"

    assert {:ok, persisted} = Persistence.fetch_room_snapshot("room-state-1")
    assert persisted.status == "publication_ready"
    assert length(persisted.turns) == 3
  end

  defp architect_result do
    %{
      "job_id" => "job-architect-1",
      "participant_id" => "architect",
      "participant_role" => "architect",
      "status" => "completed",
      "summary" => "architect proposed a shared mutable packet",
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
        %{
          "event_type" => "tool_call",
          "payload" => %{"tool_name" => "context.read", "status" => "ok"}
        }
      ],
      "events" => [%{"type" => "assistant_delta"}],
      "approvals" => [],
      "artifacts" => [],
      "execution" => %{"status" => "completed", "provider" => "claude", "text" => "{}"}
    }
  end

  defp skeptic_result do
    %{
      "job_id" => "job-skeptic-1",
      "participant_id" => "skeptic",
      "participant_role" => "skeptic",
      "status" => "completed",
      "summary" => "skeptic opened one concrete objection",
      "actions" => [
        %{
          "op" => "OBJECT",
          "title" => "Conflict handling is underspecified",
          "body" => "The packet flow does not define how contradictory tool output is preserved.",
          "targets" => [%{"entry_ref" => "claim:1"}],
          "severity" => "high"
        }
      ],
      "tool_events" => [
        %{
          "event_type" => "tool_call",
          "payload" => %{"tool_name" => "critique.scan", "status" => "ok"}
        }
      ],
      "events" => [%{"type" => "assistant_delta"}],
      "approvals" => [],
      "artifacts" => [],
      "execution" => %{"status" => "completed", "provider" => "claude", "text" => "{}"}
    }
  end

  defp resolver_result do
    %{
      "job_id" => "job-architect-2",
      "participant_id" => "architect",
      "participant_role" => "architect",
      "status" => "completed",
      "summary" => "architect resolved the objection",
      "actions" => [
        %{
          "op" => "REVISE",
          "title" => "Contradiction ledger",
          "body" => "Keep a contradiction ledger in the shared envelope.",
          "targets" => [%{"dispute_id" => "dispute:1"}]
        },
        %{
          "op" => "DECIDE",
          "title" => "Ready to publish",
          "body" => "The room is publishable after the contradiction ledger revision.",
          "targets" => [%{"dispute_id" => "dispute:1"}]
        }
      ],
      "tool_events" => [
        %{
          "event_type" => "tool_call",
          "payload" => %{"tool_name" => "revision.apply", "status" => "ok"}
        }
      ],
      "events" => [%{"type" => "assistant_delta"}],
      "approvals" => [],
      "artifacts" => [],
      "execution" => %{"status" => "completed", "provider" => "claude", "text" => "{}"}
    }
  end
end
