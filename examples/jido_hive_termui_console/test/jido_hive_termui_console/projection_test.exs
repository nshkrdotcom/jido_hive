defmodule JidoHiveTermuiConsole.ProjectionTest do
  use ExUnit.Case, async: true

  alias JidoHiveTermuiConsole.Projection

  defp snapshot do
    %{
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
          "derived" => %{"stale_ancestor" => true},
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
        }
      ]
    }
  end

  test "formats context markers including binding and conflict" do
    assert Projection.context_lines(snapshot(), 1) == [
             "DECISION",
             "  Rollback registry deploy [in:0 out:0]",
             "CONTRADICTION",
             "> Datadog says Redis is fine [in:0 out:1] [CONFLICT]",
             "BELIEF",
             "  Redis timeout [in:1 out:2] [STALE] [CONFLICT] [BINDING]"
           ]
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
end
