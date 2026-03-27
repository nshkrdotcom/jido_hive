defmodule JidoHiveServer.Collaboration.RoomServerTest do
  use ExUnit.Case, async: false

  alias JidoHiveServer.Collaboration.RoomServer

  test "records claim and evidence entries, then opens a dispute for an objection" do
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
               "round" => 1,
               "prompt_packet" => %{
                 "brief" => "Design the protocol.",
                 "context_summary" => "No prior context.",
                 "rules" => ["Every objection must target a claim."]
               }
             })

    assert opened.current_turn.participant_id == "architect"

    assert {:ok, after_architect} = RoomServer.apply_result(room, architect_result())

    assert Enum.map(after_architect.context_entries, & &1.entry_type) == ["claim", "evidence"]

    assert {:ok, _opened_again} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-skeptic-1",
               "participant_id" => "skeptic",
               "round" => 2,
               "prompt_packet" => %{
                 "brief" => "Critique the proposal.",
                 "context_summary" => "Architect proposed a shared packet flow.",
                 "rules" => ["Every objection must target a claim."]
               }
             })

    assert {:ok, after_skeptic} = RoomServer.apply_result(room, skeptic_result())

    assert Enum.map(after_skeptic.context_entries, & &1.entry_type) == [
             "claim",
             "evidence",
             "objection"
           ]

    assert Enum.any?(after_skeptic.disputes, &(&1.status == :open))
  end

  defp architect_result do
    %{
      "job_id" => "job-architect-1",
      "participant_id" => "architect",
      "participant_role" => "architect",
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
        }
      ],
      "tool_events" => [
        %{
          "tool_name" => "context.read",
          "status" => "ok",
          "input" => %{"scope" => "room"},
          "output" => %{"summary" => "No prior context."}
        }
      ]
    }
  end

  defp skeptic_result do
    %{
      "job_id" => "job-skeptic-1",
      "participant_id" => "skeptic",
      "participant_role" => "skeptic",
      "summary" => "skeptic opened one concrete objection",
      "actions" => [
        %{
          "op" => "OBJECT",
          "title" => "Conflict handling is underspecified",
          "body" =>
            "The packet flow does not yet define how contradictory tool output is preserved.",
          "targets" => [%{"entry_ref" => "claim:1"}],
          "severity" => "high"
        }
      ],
      "tool_events" => [
        %{
          "tool_name" => "critique.scan",
          "status" => "ok",
          "input" => %{"focus" => "conflicts"},
          "output" => %{"issue_count" => 1}
        }
      ]
    }
  end
end
