defmodule JidoHiveServer.PublicationsTest do
  use ExUnit.Case, async: false

  alias JidoHiveServer.Collaboration.RoomServer
  alias JidoHiveServer.Publications

  test "builds GitHub and Notion publication drafts from the shared room state" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-publications-1",
         session_id: "session-room-publications-1",
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

    assert {:ok, _opened} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-architect-publications-1",
               "participant_id" => "architect",
               "round" => 1,
               "prompt_packet" => %{
                 "brief" => "Design the protocol.",
                 "context_summary" => "No prior context.",
                 "rules" => ["Every objection must target a claim."]
               }
             })

    assert {:ok, _after_architect} = RoomServer.apply_result(room, architect_result())

    assert {:ok, _opened_again} =
             RoomServer.open_turn(room, %{
               "job_id" => "job-skeptic-publications-1",
               "participant_id" => "skeptic",
               "round" => 2,
               "prompt_packet" => %{
                 "brief" => "Critique the proposal.",
                 "context_summary" => "Architect proposed a shared packet flow.",
                 "rules" => ["Every objection must target a claim."]
               }
             })

    assert {:ok, snapshot} = RoomServer.apply_result(room, skeptic_result())

    plan = Publications.build_plan(snapshot)
    assert plan.room_id == "room-publications-1"
    assert plan.requested

    github_plan = Enum.find(plan.publications, &(&1.channel == "github"))
    assert github_plan.capability_id == "github.issue.create"
    assert github_plan.draft.title =~ "client-server collaboration protocol"
    assert github_plan.draft.body =~ "Shared packet"
    assert github_plan.draft.body =~ "Conflict handling is underspecified"

    notion_plan = Enum.find(plan.publications, &(&1.channel == "notion"))
    assert notion_plan.capability_id == "notion.pages.create"
    assert notion_plan.draft.title =~ "client-server collaboration protocol"
    assert is_list(notion_plan.draft.children)
    assert length(notion_plan.draft.children) >= 3
  end

  defp architect_result do
    %{
      "job_id" => "job-architect-publications-1",
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
        },
        %{
          "op" => "PUBLISH",
          "title" => "Publish the reviewed protocol",
          "body" =>
            "Prepare both a GitHub issue draft and a Notion page draft from the shared room state."
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
      "job_id" => "job-skeptic-publications-1",
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
