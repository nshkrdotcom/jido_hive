defmodule JidoHiveServer.Collaboration.ContextGraphTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.ContextGraph
  alias JidoHiveServer.Collaboration.Schema.ContextEdge

  test "normalizes inline relations into outgoing and incoming edge indexes" do
    room = room_snapshot()

    projection = ContextGraph.build(room)

    assert %ContextEdge{
             from_id: "decision-1",
             to_id: "question-1",
             type: :resolves
           } = hd(projection.outgoing["decision-1"])

    assert Enum.map(projection.outgoing["note-1"], &{&1.from_id, &1.to_id, &1.type}) == [
             {"note-1", "decision-1", :references},
             {"note-1", "fact-1", :derives_from}
           ]

    assert Enum.map(projection.incoming["decision-1"], &{&1.from_id, &1.to_id, &1.type}) == [
             {"note-1", "decision-1", :references},
             {"counterpoint-1", "decision-1", :contradicts}
           ]
  end

  test "returns adjacency for a context node" do
    room = room_snapshot() |> ContextGraph.attach()

    assert %{
             outgoing: [
               %ContextEdge{type: :references, to_id: "decision-1"},
               %ContextEdge{type: :derives_from, to_id: "fact-1"}
             ],
             incoming: [
               %ContextEdge{type: :derives_from, from_id: "artifact-1"},
               %ContextEdge{type: :supports, from_id: "artifact-1"},
               %ContextEdge{type: :resolves, from_id: "resolution-1"}
             ]
           } = ContextGraph.adjacency(room, "note-1")
  end

  test "returns breadth-first provenance chains with deterministic ordering" do
    room = room_snapshot() |> ContextGraph.attach()

    assert Enum.map(ContextGraph.provenance_chain(room, "artifact-1"), & &1.context_id) == [
             "note-1",
             "fact-1"
           ]
  end

  test "returns unresolved contradiction edges only" do
    room = room_snapshot() |> ContextGraph.attach()

    assert Enum.map(ContextGraph.contradictions(room), &{&1.from_id, &1.to_id, &1.type}) == [
             {"counterpoint-1", "decision-1", :contradicts}
           ]
  end

  test "returns open questions resolved only by decision or artifact context objects" do
    room = room_snapshot() |> ContextGraph.attach()

    assert Enum.map(ContextGraph.open_questions(room), & &1.context_id) == ["question-2"]
  end

  test "returns nodes with no incoming derives_from edges as derivation roots" do
    room = room_snapshot() |> ContextGraph.attach()

    assert Enum.map(ContextGraph.derivation_roots(room), & &1.context_id) == [
             "question-1",
             "question-2",
             "decision-1",
             "artifact-1",
             "counterpoint-1",
             "resolution-1"
           ]
  end

  defp room_snapshot do
    %{
      context_objects: [
        context_object("question-1", "question", ~U[2026-04-06 01:00:00Z]),
        context_object("question-2", "question", ~U[2026-04-06 01:05:00Z]),
        context_object("fact-1", "fact", ~U[2026-04-06 01:10:00Z]),
        context_object(
          "decision-1",
          "decision",
          ~U[2026-04-06 01:20:00Z],
          [%{relation: "resolves", target_id: "question-1"}]
        ),
        context_object(
          "note-1",
          "note",
          ~U[2026-04-06 01:30:00Z],
          [
            %{relation: "derives_from", target_id: "fact-1"},
            %{relation: "references", target_id: "decision-1"}
          ]
        ),
        context_object(
          "artifact-1",
          "artifact",
          ~U[2026-04-06 01:40:00Z],
          [
            %{relation: "derives_from", target_id: "note-1"},
            %{relation: "resolves", target_id: "question-1"},
            %{relation: "supports", target_id: "note-1"}
          ]
        ),
        context_object(
          "counterpoint-1",
          "note",
          ~U[2026-04-06 01:50:00Z],
          [%{relation: "contradicts", target_id: "decision-1"}]
        ),
        context_object(
          "resolution-1",
          "decision",
          ~U[2026-04-06 02:00:00Z],
          [
            %{relation: "resolves", target_id: "note-1"},
            %{relation: "resolves", target_id: "counterpoint-1"}
          ]
        )
      ]
    }
  end

  defp context_object(context_id, object_type, inserted_at, relations \\ []) do
    %{
      context_id: context_id,
      object_type: object_type,
      title: context_id,
      inserted_at: inserted_at,
      relations: relations
    }
  end
end
