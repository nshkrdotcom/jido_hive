defmodule JidoHiveServer.Collaboration.ContextQueryTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.ContextQuery

  defp snapshot do
    %{
      context_objects: [
        %{
          context_id: "q-1",
          object_type: "question",
          title: "What broke?",
          authored_by: %{participant_id: "alice"},
          relations: []
        },
        %{
          context_id: "q-2",
          object_type: "question",
          title: "When did it start?",
          authored_by: %{participant_id: "bob"},
          relations: []
        },
        %{
          context_id: "h-1",
          object_type: "hypothesis",
          title: "Redis dropped connections",
          authored_by: %{participant_id: "alice"},
          relations: []
        },
        %{
          context_id: "e-1",
          object_type: "evidence",
          title: "Auth timeout logs",
          authored_by: %{participant_id: "alice"},
          relations: [%{relation: "supports", target_id: "h-1"}]
        },
        %{
          context_id: "c-1",
          object_type: "contradiction",
          title: "Datadog shows Redis healthy",
          authored_by: %{participant_id: "bob"},
          relations: [%{relation: "contradicts", target_id: "h-1"}]
        },
        %{
          context_id: "f-1",
          object_type: "fact",
          title: "Registry deploy was yesterday",
          authored_by: %{participant_id: "bob"},
          relations: [%{relation: "answers", target_id: "q-2"}]
        },
        %{
          context_id: "d-1",
          object_type: "decision",
          title: "Rollback the registry deploy",
          authored_by: %{participant_id: "alice"},
          relations: [%{relation: "derived_from", target_id: "h-1"}]
        }
      ]
    }
  end

  test "filters visible room objects" do
    participant = %{"participant_id" => "alice", "participant_role" => "analyst"}

    objects =
      [
        %{"context_id" => "ctx-room", "scope" => %{"read" => ["room"]}},
        %{
          "context_id" => "ctx-author",
          "scope" => %{"read" => ["author"]},
          "authored_by" => %{"participant_id" => "alice"}
        },
        %{
          "context_id" => "ctx-other",
          "scope" => %{"read" => ["participant:bob"]},
          "authored_by" => %{"participant_id" => "bob"}
        }
      ]

    assert Enum.map(
             ContextQuery.visible_context_objects(objects, participant),
             & &1["context_id"]
           ) == [
             "ctx-room",
             "ctx-author"
           ]
  end

  test "queries by type and author" do
    assert Enum.map(
             ContextQuery.list_by_type(snapshot(), ["hypothesis", "decision"]),
             & &1.context_id
           ) == [
             "h-1",
             "d-1"
           ]

    assert Enum.map(ContextQuery.list_by_author(snapshot(), "alice"), & &1.context_id) == [
             "q-1",
             "h-1",
             "e-1",
             "d-1"
           ]
  end

  test "finds adjacent objects and unresolved questions" do
    assert Enum.map(ContextQuery.adjacent_objects(snapshot(), "h-1"), & &1.context_id) == [
             "e-1",
             "c-1",
             "d-1"
           ]

    assert Enum.map(ContextQuery.open_questions(snapshot()), & &1.context_id) == ["q-1"]
  end

  test "returns active hypotheses, contradictions, and accepted decisions" do
    assert Enum.map(ContextQuery.active_hypotheses(snapshot()), & &1.context_id) == ["h-1"]
    assert Enum.map(ContextQuery.contradictions(snapshot()), & &1.context_id) == ["h-1", "c-1"]
    assert Enum.map(ContextQuery.accepted_decisions(snapshot()), & &1.context_id) == ["d-1"]
  end
end
