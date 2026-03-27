defmodule JidoHiveServer.PublicationsTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias JidoHiveServer.Persistence
  alias JidoHiveServer.Publications

  defmodule GatewayStub do
    @behaviour JidoHiveServer.Publications.Gateway

    @impl true
    def invoke_publication(plan, input, _opts) do
      {:ok,
       %{
         run: %{run_id: "run-#{plan.channel}", status: :completed},
         output: %{"channel" => plan.channel, "input" => input}
       }}
    end
  end

  setup do
    old_gateway = Application.get_env(:jido_hive_server, :publication_gateway)
    Application.put_env(:jido_hive_server, :publication_gateway, GatewayStub)

    on_exit(fn ->
      if old_gateway do
        Application.put_env(:jido_hive_server, :publication_gateway, old_gateway)
      else
        Application.delete_env(:jido_hive_server, :publication_gateway)
      end
    end)

    :ok
  end

  test "builds GitHub and Notion publication drafts and persists execution runs" do
    snapshot = publication_ready_snapshot()

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

    assert {:ok, execution} =
             Publications.execute(snapshot, %{
               "channels" => ["github", "notion"],
               "connections" => %{
                 "github" => "connection-github-1",
                 "notion" => "connection-notion-1"
               },
               "bindings" => %{
                 "github" => %{"repo" => "owner/repo"},
                 "notion" => %{
                   "parent.data_source_id" => "data-source-1",
                   "title_property" => "Name"
                 }
               },
               "actor_id" => "operator-1",
               "tenant_id" => "workspace-1"
             })

    assert execution.room_id == "room-publications-1"
    assert Enum.all?(execution.runs, &(&1.status == "completed"))

    persisted = Persistence.list_publication_runs("room-publications-1")
    assert length(persisted) == 2
    assert Enum.any?(persisted, &(&1.channel == "github"))
    assert Enum.any?(persisted, &(&1.channel == "notion"))
  end

  defp publication_ready_snapshot do
    %{
      room_id: "room-publications-1",
      session_id: "session-room-publications-1",
      brief: "Design a client-server collaboration protocol for AI agents.",
      rules: ["Every objection must target a claim."],
      participants: [],
      turns: [
        %{
          job_id: "job-architect-1",
          participant_role: "architect",
          phase: "proposal",
          result_summary: "architect proposed a shared mutable packet",
          tool_events: [
            %{"event_type" => "tool_call", "payload" => %{"tool_name" => "context.read"}}
          ],
          artifacts: []
        },
        %{
          job_id: "job-skeptic-1",
          participant_role: "skeptic",
          phase: "critique",
          result_summary: "skeptic opened one concrete objection",
          tool_events: [
            %{"event_type" => "tool_call", "payload" => %{"tool_name" => "critique.scan"}}
          ],
          artifacts: []
        }
      ],
      context_entries: [
        %{
          entry_ref: "claim:1",
          entry_type: "claim",
          participant_role: "architect",
          title: "Shared packet",
          body: "The server should own a shared packet of instructions, context, and refs."
        },
        %{
          entry_ref: "evidence:2",
          entry_type: "evidence",
          participant_role: "architect",
          title: "Packet lineage",
          body: "Each turn should carry the prior structured actions and tool traces forward."
        },
        %{
          entry_ref: "publish_request:3",
          entry_type: "publish_request",
          participant_role: "architect",
          title: "Publish the reviewed protocol",
          body: "Prepare both a GitHub issue and a Notion page from the room."
        },
        %{
          entry_ref: "objection:4",
          entry_type: "objection",
          participant_role: "skeptic",
          title: "Conflict handling is underspecified",
          body: "The packet flow does not yet define how contradictory tool output is preserved."
        }
      ],
      disputes: [
        %{
          dispute_id: "dispute:1",
          title: "Conflict handling is underspecified",
          severity: "high",
          status: :resolved,
          opened_by_entry_ref: "objection:4",
          target_entry_refs: ["claim:1"]
        }
      ],
      current_turn: %{},
      status: "publication_ready",
      phase: "publication_ready",
      round: 3,
      next_entry_seq: 5,
      next_dispute_seq: 2
    }
  end
end
