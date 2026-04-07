defmodule JidoHiveServer.Collaboration.ContextManagerTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.{ContextGraph, ContextManager}

  test "allows append intents that stay within writable types, writable supersedes targets, and readable relation targets" do
    room = scoped_room() |> ContextGraph.attach()

    participant = %{
      participant_id: "worker-1",
      participant_role: "analyst",
      participant_kind: "runtime"
    }

    write_intent = %{
      drafted_object_types: ["note"],
      relation_targets_by_type: %{
        references: ["shared-2"],
        supersedes: ["owned-1"]
      }
    }

    assert :ok = ContextManager.validate_append(participant, write_intent, room)
  end

  test "rejects append intents that supersede nodes outside the participant writable scope" do
    room = scoped_room() |> ContextGraph.attach()

    participant = %{
      participant_id: "worker-1",
      participant_role: "analyst",
      participant_kind: "runtime"
    }

    write_intent = %{
      drafted_object_types: ["note"],
      relation_targets_by_type: %{
        supersedes: ["shared-1"]
      }
    }

    assert {:error, {:scope_violation, %{kind: :supersedes_target, target_id: "shared-1"}}} =
             ContextManager.validate_append(participant, write_intent, room)
  end

  test "rejects read-governed relation targets beyond the allowed references hop limit" do
    room = scoped_room() |> ContextGraph.attach()

    participant = %{
      participant_id: "worker-1",
      participant_role: "analyst",
      participant_kind: "runtime"
    }

    write_intent = %{
      drafted_object_types: ["note"],
      relation_targets_by_type: %{
        references: ["blocked-1"]
      }
    }

    assert {:error, {:scope_violation, %{kind: :relation_target, target_id: "blocked-1"}}} =
             ContextManager.validate_append(participant, write_intent, room)
  end

  test "builds assignment views from the task anchor with a depth-2 traversal bound" do
    room = assignment_view_room() |> ContextGraph.attach()

    participant = %{
      participant_id: "worker-2",
      participant_role: "analyst",
      participant_kind: "runtime"
    }

    task_context = %{
      mode: :assignment,
      anchor_context_id: "anchor-1",
      objective: "Review the local context."
    }

    assert Enum.map(ContextManager.build_view(participant, task_context, room), & &1.context_id) ==
             [
               "anchor-1",
               "root-1",
               "shared-1",
               "far-1"
             ]
  end

  test "human pane views surface only unresolved contradictions and open questions" do
    room = human_pane_room() |> ContextGraph.attach()

    participant = %{
      participant_id: "human-1",
      participant_role: "reviewer",
      participant_kind: "human"
    }

    task_context = %{
      mode: :human_pane,
      anchor_context_id: nil,
      objective: "Watch the room."
    }

    assert Enum.map(ContextManager.build_view(participant, task_context, room), & &1.context_id) ==
             [
               "question-2",
               "decision-1",
               "counterpoint-1"
             ]
  end

  test "after_append emits contradiction events with deterministic heterogeneity classification" do
    before_room =
      %{
        context_objects: [
          context_object("decision-1", "decision", ~U[2026-04-06 06:00:00Z], [],
            provenance: %{authority_level: "binding"},
            authored_by: %{capability_id: "cap-a"}
          )
        ]
      }
      |> ContextGraph.attach()

    after_room =
      %{
        before_room
        | context_objects:
            before_room.context_objects ++
              [
                context_object(
                  "counterpoint-1",
                  "note",
                  ~U[2026-04-06 06:05:00Z],
                  [%{relation: "contradicts", target_id: "decision-1"}],
                  provenance: %{authority_level: "advisory"},
                  authored_by: %{capability_id: "cap-b"}
                )
              ]
      }
      |> ContextGraph.attach()

    assert %{
             room_events: [
               %{
                 type: :contradiction_detected,
                 payload: %{
                   left_context_id: "counterpoint-1",
                   right_context_id: "decision-1",
                   heterogeneity_class: :authority,
                   detected_from_context_ids: ["counterpoint-1"]
                 }
               }
             ],
             context_annotations: %{}
           } = ContextManager.after_append(before_room, after_room, ["counterpoint-1"])
  end

  test "after_append emits downstream invalidation events and stale annotations for superseded ancestors" do
    before_room =
      %{
        context_objects: [
          context_object("fact-1", "fact", ~U[2026-04-06 07:00:00Z]),
          context_object(
            "note-1",
            "note",
            ~U[2026-04-06 07:05:00Z],
            [%{relation: "derives_from", target_id: "fact-1"}]
          ),
          context_object(
            "artifact-1",
            "artifact",
            ~U[2026-04-06 07:10:00Z],
            [%{relation: "derives_from", target_id: "note-1"}]
          )
        ]
      }
      |> ContextGraph.attach()

    after_room =
      %{
        before_room
        | context_objects:
            before_room.context_objects ++
              [
                context_object(
                  "fact-2",
                  "fact",
                  ~U[2026-04-06 07:15:00Z],
                  [%{relation: "supersedes", target_id: "fact-1"}]
                )
              ]
      }
      |> ContextGraph.attach()

    assert %{
             room_events: [
               %{
                 type: :downstream_invalidated,
                 payload: %{
                   source_context_id: "fact-2",
                   superseded_context_ids: ["fact-1"],
                   invalidated_context_ids: ["artifact-1", "note-1"],
                   reason: :supersedes
                 }
               }
             ],
             context_annotations: %{
               "artifact-1" => %{stale_ancestor: true, stale_due_to_ids: ["fact-1"]},
               "note-1" => %{stale_ancestor: true, stale_due_to_ids: ["fact-1"]}
             }
           } = ContextManager.after_append(before_room, after_room, ["fact-2"])
  end

  defp scoped_room do
    %{
      context_config: %{
        participant_scopes: %{
          "worker-1" => %{
            writable_types: ["note"],
            writable_node_ids: ["owned-1"],
            reference_hop_limit: 2
          }
        }
      },
      context_objects: [
        context_object(
          "owned-1",
          "note",
          ~U[2026-04-06 03:00:00Z],
          [%{relation: "references", target_id: "shared-1"}]
        ),
        context_object(
          "shared-1",
          "evidence",
          ~U[2026-04-06 03:05:00Z],
          [%{relation: "references", target_id: "shared-2"}]
        ),
        context_object(
          "shared-2",
          "artifact",
          ~U[2026-04-06 03:10:00Z],
          [%{relation: "references", target_id: "blocked-1"}]
        ),
        context_object("blocked-1", "decision", ~U[2026-04-06 03:15:00Z])
      ]
    }
  end

  defp assignment_view_room do
    %{
      context_config: %{participant_scopes: %{}},
      context_objects: [
        context_object("root-1", "fact", ~U[2026-04-06 04:00:00Z]),
        context_object(
          "anchor-1",
          "note",
          ~U[2026-04-06 04:05:00Z],
          [
            %{relation: "derives_from", target_id: "root-1"},
            %{relation: "references", target_id: "shared-1"}
          ]
        ),
        context_object(
          "shared-1",
          "evidence",
          ~U[2026-04-06 04:10:00Z],
          [%{relation: "references", target_id: "far-1"}]
        ),
        context_object(
          "far-1",
          "artifact",
          ~U[2026-04-06 04:15:00Z],
          [%{relation: "references", target_id: "far-2"}]
        ),
        context_object(
          "far-2",
          "note",
          ~U[2026-04-06 04:20:00Z],
          [%{relation: "references", target_id: "far-3"}]
        ),
        context_object("far-3", "note", ~U[2026-04-06 04:25:00Z])
      ]
    }
  end

  defp human_pane_room do
    %{
      context_config: %{participant_scopes: %{}},
      context_objects: [
        context_object("question-1", "question", ~U[2026-04-06 05:00:00Z]),
        context_object("question-2", "question", ~U[2026-04-06 05:05:00Z]),
        context_object(
          "decision-1",
          "decision",
          ~U[2026-04-06 05:10:00Z],
          [%{relation: "resolves", target_id: "question-1"}]
        ),
        context_object(
          "counterpoint-1",
          "note",
          ~U[2026-04-06 05:15:00Z],
          [%{relation: "contradicts", target_id: "decision-1"}]
        ),
        context_object(
          "resolution-1",
          "decision",
          ~U[2026-04-06 05:20:00Z],
          [
            %{relation: "resolves", target_id: "counterpoint-1"},
            %{relation: "resolves", target_id: "question-1"}
          ]
        )
      ]
    }
  end

  defp context_object(context_id, object_type, inserted_at, relations \\ [], opts \\ []) do
    %{
      context_id: context_id,
      object_type: object_type,
      title: context_id,
      scope: %{read: ["room"], write: ["author"]},
      authored_by: Keyword.get(opts, :authored_by, %{}),
      provenance: Keyword.get(opts, :provenance, %{}),
      relations: relations,
      inserted_at: inserted_at
    }
  end
end
