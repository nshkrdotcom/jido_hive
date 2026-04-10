defmodule JidoHiveConsole.ProjectionTest do
  use ExUnit.Case, async: true

  alias JidoHiveConsole.Projection

  defp snapshot do
    %{
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
      "timeline" => [
        %{"body" => "Investigating auth timeout", "metadata" => %{"participant_id" => "alice"}},
        %{"body" => "Redis is healthy", "metadata" => %{"participant_id" => "bob"}}
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

  test "formats grouped context rows with lighter zero-noise badges" do
    assert Projection.context_lines(snapshot(), 1) == [
             "DECISIONS",
             "  Rollback registry deploy",
             "CONFLICTS",
             "> Datadog says Redis is fine [in:0 out:1] [CONFLICT]",
             "WORKING BELIEFS",
             "  Redis timeout · ctx-1 [in:1 out:2] [DUP:1] [STALE] [CONFLICT] [BINDING]"
           ]
  end

  test "builds an operator workflow summary from the shared workflow contract" do
    summary = Projection.workflow_summary(snapshot())

    assert summary.objective == "Stabilize the Redis auth path"
    assert summary.stage == "Resolve contradictions"
    assert summary.next_action =~ "binding resolution"
    assert summary.reason == "Open contradictions remain"
    assert summary.graph_counts =~ "1 decision"
    assert summary.graph_counts =~ "2 contradictions"
    assert summary.graph_counts =~ "1 duplicate"
  end

  test "renders selected context detail lines for the operator detail pane" do
    selected =
      snapshot()
      |> Projection.display_context_objects()
      |> Enum.at(1)

    lines = Projection.selected_context_detail_lines(selected, snapshot())

    assert lines |> Enum.join("\n") =~ "Context ID: ctx-2"
    assert lines |> Enum.join("\n") =~ "Type: contradiction"
    assert lines |> Enum.join("\n") =~ "Graph: 0 incoming · 1 outgoing"
    assert lines |> Enum.join("\n") =~ "Body"
  end

  test "renders duplicate collapse details for canonical graph entries" do
    selected =
      snapshot()
      |> Projection.display_context_objects()
      |> Enum.at(2)

    lines = Projection.selected_context_detail_lines(selected, snapshot())

    assert lines |> Enum.join("\n") =~ "Duplicates: 1 collapsed under ctx-1"
    assert lines |> Enum.join("\n") =~ "Group: ctx-1, ctx-4"
  end

  test "builds cycle-safe provenance trees" do
    [header | rest] =
      snapshot()
      |> Map.fetch!("context_objects")
      |> then(fn objects ->
        Projection.provenance_tree(Enum.at(objects, 0), objects)
      end)

    assert header == "[BELIEF] Redis timeout"
    assert Enum.any?(rest, &String.contains?(&1, "[cycle"))
  end

  test "detects conflicts from relations when adjacency is absent" do
    snapshot = %{
      "context_objects" => [
        %{
          "context_id" => "ctx-1",
          "object_type" => "decision",
          "title" => "Base claim",
          "relations" => []
        },
        %{
          "context_id" => "ctx-2",
          "object_type" => "note",
          "title" => "Contradicting note",
          "relations" => [%{"relation" => "contradicts", "target_id" => "ctx-1"}]
        }
      ]
    }

    [base_claim, contradicting_note] = snapshot["context_objects"]

    assert Projection.conflict?(base_claim, snapshot)
    assert Projection.conflict?(contradicting_note, snapshot)
  end

  test "renders lobby flags from room status" do
    rows = [
      %{
        room_id: "a",
        brief: "ready",
        status: "publication_ready",
        dispatch_policy_id: "rr",
        completed_slots: 2,
        total_slots: 2,
        participant_count: 2,
        flagged: false,
        fetch_error: false
      },
      %{
        room_id: "b",
        brief: "conflict",
        status: "needs_resolution",
        dispatch_policy_id: "rr",
        completed_slots: 1,
        total_slots: 2,
        participant_count: 2,
        flagged: true,
        fetch_error: false
      },
      %{
        room_id: "c",
        brief: "failed",
        status: "failed",
        dispatch_policy_id: "rr",
        completed_slots: 1,
        total_slots: 2,
        participant_count: 2,
        flagged: false,
        fetch_error: false
      }
    ]

    lines = Projection.lobby_rows(rows, 0, 120)
    assert Enum.any?(lines, &String.contains?(&1, "PUB"))
    assert Enum.any?(lines, &String.contains?(&1, "⚡"))
    assert Enum.any?(lines, &String.contains?(&1, "✗"))
  end

  test "renders conversation from contributions and preserves a pending local echo" do
    snapshot = %{
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
      ]
    }

    assert Projection.conversation_lines(snapshot, limit: 10) == [
             "alice: plain hello",
             "worker-01 [reasoning]: Need a concrete discussion target."
           ]

    assert Projection.conversation_lines(snapshot,
             limit: 10,
             participant_id: "alice",
             pending_submit: %{text: "still syncing"}
           ) == [
             "alice: plain hello",
             "worker-01 [reasoning]: Need a concrete discussion target.",
             "alice (sending): still syncing"
           ]
  end

  test "falls back to message context objects when the room snapshot omits contributions" do
    snapshot = %{
      "context_objects" => [
        %{
          "context_id" => "ctx-message-1",
          "object_type" => "message",
          "title" => "alice said",
          "body" => "hello from context",
          "authored_by" => %{"participant_id" => "alice"}
        }
      ]
    }

    assert Projection.conversation_lines(snapshot) == ["alice: hello from context"]
  end
end
