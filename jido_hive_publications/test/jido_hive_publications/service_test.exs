defmodule JidoHivePublications.ServiceTest do
  use ExUnit.Case, async: false
  use JidoHivePublications.PersistenceCase

  alias JidoHivePublications
  alias JidoHivePublications.Service

  defmodule GatewayStub do
    @behaviour JidoHivePublications.Service.Gateway

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
    old_gateway = Application.get_env(:jido_hive_publications, :publication_gateway)
    Application.put_env(:jido_hive_publications, :publication_gateway, GatewayStub)

    on_exit(fn ->
      if old_gateway do
        Application.put_env(:jido_hive_publications, :publication_gateway, old_gateway)
      else
        Application.delete_env(:jido_hive_publications, :publication_gateway)
      end
    end)

    :ok
  end

  test "builds GitHub and Notion publication drafts and persists execution runs" do
    snapshot = publication_ready_snapshot()

    plan = Service.build_plan(snapshot)
    assert plan.room_id == "room-publications-1"
    assert plan.requested
    assert plan.duplicate_policy == "canonical_only"
    assert plan.source_entries == ["ctx-1", "ctx-2", "ctx-3", "ctx-4"]

    github_plan = Enum.find(plan.publications, &(&1.channel == "github"))
    assert github_plan.capability_id == "github.issue.create"
    assert github_plan.draft.title =~ "client-server collaboration protocol"
    assert github_plan.draft.body =~ "Shared packet"
    assert github_plan.draft.body =~ "Conflict handling is underspecified"
    assert String.split(github_plan.draft.body, "Shared packet") |> length() == 2

    notion_plan = Enum.find(plan.publications, &(&1.channel == "notion"))
    assert notion_plan.capability_id == "notion.pages.create"
    assert notion_plan.draft.title =~ "client-server collaboration protocol"
    assert is_list(notion_plan.draft.children)
    assert length(notion_plan.draft.children) >= 3

    assert {:ok, execution} =
             JidoHivePublications.start_publication_run(snapshot, %{
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

    assert {:ok, persisted} =
             JidoHivePublications.list_publication_runs("room-publications-1", [])

    assert length(persisted) == 2
    assert Enum.any?(persisted, &(&1.channel == "github"))
    assert Enum.any?(persisted, &(&1.channel == "notion"))

    github_run = Enum.find(persisted, &(&1.channel == "github"))

    assert {:ok, fetched} =
             JidoHivePublications.fetch_publication_run("room-publications-1", github_run.id)

    assert fetched.status == "completed"
  end

  defp publication_ready_snapshot do
    %{
      room_id: "room-publications-1",
      brief: "Design a client-server collaboration protocol for AI agents.",
      config: %{"rules" => ["Every objection must target a claim."]},
      context_objects: [
        %{
          context_id: "ctx-1",
          object_type: "belief",
          title: "Publish the reviewed protocol",
          body: "Prepare both a GitHub issue and a Notion page from the room."
        },
        %{
          context_id: "ctx-2",
          object_type: "belief",
          title: "Shared packet",
          body: "The server should own a shared packet of instructions, context, and refs."
        },
        %{
          context_id: "ctx-5",
          object_type: "belief",
          title: "Shared packet",
          body: "The server should own a shared packet of instructions, context, and refs."
        },
        %{
          context_id: "ctx-3",
          object_type: "evidence",
          title: "Packet lineage",
          body: "Each turn should carry the prior structured actions and tool traces forward."
        },
        %{
          context_id: "ctx-4",
          object_type: "question",
          title: "Conflict handling is underspecified",
          body: "The packet flow does not yet define how contradictory tool output is preserved."
        }
      ],
      contributions: [
        %{
          participant_role: "architect",
          contribution_type: "publish_request",
          authority_level: "binding",
          summary: "Publish the reviewed protocol"
        }
      ],
      status: "publication_ready"
    }
  end
end
