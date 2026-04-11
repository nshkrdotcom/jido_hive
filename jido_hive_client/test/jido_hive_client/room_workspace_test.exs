defmodule JidoHiveClient.RoomWorkspaceTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.RoomWorkspace

  defp snapshot do
    %{
      "room_id" => "room-1",
      "brief" => "Stabilize the Redis auth path",
      "status" => "running",
      "workflow_summary" => %{
        "objective" => "Stabilize the Redis auth path",
        "stage" => "Resolve contradictions",
        "next_action" => "Review ctx-2 and submit a binding resolution",
        "blockers" => [%{"kind" => "contradiction", "count" => 2}],
        "publish_ready" => false,
        "publish_blockers" => ["Open contradictions remain"],
        "graph_counts" => %{
          "decisions" => 1,
          "questions" => 0,
          "contradictions" => 2,
          "duplicates" => 1,
          "stale" => 1,
          "total" => 3
        },
        "focus_candidates" => [%{"kind" => "contradiction", "context_id" => "ctx-2"}]
      },
      "contributions" => [
        %{
          "participant_id" => "alice",
          "contribution_type" => "chat",
          "summary" => "plain hello"
        },
        %{
          "participant_id" => "worker-01",
          "contribution_type" => "reasoning",
          "summary" => "Need a concrete discussion target."
        }
      ],
      "timeline" => [
        %{"body" => "Investigating auth timeout", "metadata" => %{"participant_id" => "alice"}}
      ],
      "context_objects" => [
        %{
          "context_id" => "ctx-1",
          "object_type" => "belief",
          "title" => "Redis timeout",
          "provenance" => %{"authority_level" => "binding"},
          "derived" => %{
            "stale_ancestor" => true,
            "duplicate_status" => "canonical",
            "duplicate_size" => 2,
            "duplicate_context_ids" => ["ctx-1", "ctx-4"],
            "canonical_context_id" => "ctx-1"
          },
          "adjacency" => %{
            "incoming" => [%{"type" => "supports"}],
            "outgoing" => [%{"type" => "contradicts"}, %{"type" => "references"}]
          },
          "relations" => [%{"relation" => "references", "target_id" => "ctx-3"}]
        },
        %{
          "context_id" => "ctx-2",
          "object_type" => "contradiction",
          "title" => "Datadog says Redis is fine",
          "adjacency" => %{"incoming" => [], "outgoing" => [%{"type" => "contradicts"}]}
        },
        %{
          "context_id" => "ctx-3",
          "object_type" => "decision",
          "title" => "Rollback registry deploy",
          "relations" => [%{"relation" => "references", "target_id" => "ctx-1"}],
          "adjacency" => %{"incoming" => [], "outgoing" => []}
        },
        %{
          "context_id" => "ctx-4",
          "object_type" => "belief",
          "title" => "Redis timeout",
          "body" => "Auth requests are timing out.",
          "derived" => %{
            "duplicate_status" => "duplicate",
            "duplicate_size" => 2,
            "duplicate_context_ids" => ["ctx-1", "ctx-4"],
            "canonical_context_id" => "ctx-1"
          },
          "adjacency" => %{"incoming" => [], "outgoing" => []}
        }
      ]
    }
  end

  test "builds a structured room workspace with grouped graph sections" do
    workspace = RoomWorkspace.build(snapshot(), selected_context_id: "ctx-2")

    assert workspace.room_id == "room-1"
    assert workspace.control_plane.objective == "Stabilize the Redis auth path"

    assert Enum.map(workspace.graph_sections, & &1.title) == [
             "DECISIONS",
             "CONFLICTS",
             "WORKING BELIEFS"
           ]

    assert [%{context_id: "ctx-3"}] = Enum.at(workspace.graph_sections, 0).items
    assert [%{context_id: "ctx-2", selected?: true}] = Enum.at(workspace.graph_sections, 1).items

    belief = Enum.at(workspace.graph_sections, 2).items |> hd()
    assert belief.flags.binding
    assert belief.flags.conflict
    assert belief.flags.stale
    assert belief.flags.duplicate_count == 1
  end

  test "builds selected detail for the chosen context object" do
    workspace = RoomWorkspace.build(snapshot(), selected_context_id: "ctx-2")
    detail = workspace.selected_detail

    assert detail.context_id == "ctx-2"
    assert detail.object_type == "contradiction"
    assert detail.graph == %{incoming: 0, outgoing: 1}

    assert Enum.any?(detail.recommended_actions, &(&1.label == "Open conflict resolution"))
    assert Enum.any?(detail.recommended_actions, &(&1.label == "Inspect provenance"))
    assert detail.body == "[no body]"
  end

  test "builds a provenance overlay model on demand" do
    assert {:ok, provenance} = RoomWorkspace.provenance(snapshot(), "ctx-1")

    assert provenance.context_id == "ctx-1"
    assert provenance.flags.binding
    assert Enum.any?(provenance.trace, &Map.get(&1, :cycle))
  end

  test "includes pending steering messages in conversation view data" do
    workspace =
      RoomWorkspace.build(snapshot(),
        participant_id: "alice",
        pending_submit: %{text: "still syncing"}
      )

    assert Enum.at(workspace.conversation, -1) == %{
             body: "still syncing",
             contribution_type: "chat",
             participant_id: "alice",
             pending?: true
           }
  end
end
