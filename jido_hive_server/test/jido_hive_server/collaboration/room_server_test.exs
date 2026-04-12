defmodule JidoHiveServer.Collaboration.RoomServerTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias JidoHiveServer.Collaboration.RoomServer
  alias JidoHiveServer.Persistence

  test "persists assignments and contributions for a room" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-state-1",
         snapshot: %{
           room_id: "room-state-1",
           session_id: "session-room-state-1",
           brief: "Design a participation substrate.",
           rules: ["Return structured contributions only."],
           status: "idle",
           participants: [
             %{
               participant_id: "worker-01",
               participant_role: "analyst",
               participant_kind: "runtime",
               authority_level: "advisory",
               target_id: "target-worker-01",
               capability_id: "workspace.exec.session",
               metadata: %{}
             }
           ],
           current_assignment: %{},
           assignments: [],
           context_objects: [],
           contributions: [],
           dispatch_policy_id: "round_robin/v2",
           dispatch_policy_config: %{},
           dispatch_state: %{applied_event_ids: [], completed_slots: 0, total_slots: 1},
           next_context_seq: 1,
           next_assignment_seq: 1,
           next_contribution_seq: 1
         }}
      )

    assert {:ok, opened} =
             RoomServer.open_assignment(room, %{
               "assignment" => %{
                 "assignment_id" => "asn-1",
                 "room_id" => "room-state-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "analyst",
                 "target_id" => "target-worker-01",
                 "capability_id" => "workspace.exec.session",
                 "phase" => "analysis",
                 "objective" => "Analyze the brief.",
                 "contribution_contract" => %{"allowed_contribution_types" => ["reasoning"]},
                 "context_view" => %{"brief" => "Design a substrate.", "context_objects" => []},
                 "status" => "running",
                 "opened_at" => DateTime.utc_now()
               }
             })

    assert opened.current_assignment.assignment_id == "asn-1"

    assert {:ok, completed} =
             RoomServer.record_contribution(room, %{
               "contribution" => %{
                 "room_id" => "room-state-1",
                 "assignment_id" => "asn-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "analyst",
                 "target_id" => "target-worker-01",
                 "capability_id" => "workspace.exec.session",
                 "contribution_type" => "reasoning",
                 "authority_level" => "advisory",
                 "summary" => "Added a belief.",
                 "consumed_context_ids" => [],
                 "context_objects" => [
                   %{
                     "object_type" => "belief",
                     "title" => "Shared state",
                     "body" => "Server-owned state."
                   }
                 ],
                 "artifacts" => [],
                 "events" => [],
                 "tool_events" => [],
                 "approvals" => [],
                 "execution" => %{"status" => "completed"},
                 "status" => "completed",
                 "schema_version" => "jido_hive/contribution.submit.v1"
               }
             })

    assert completed.status == "publication_ready"
    assert [%{assignment_id: "asn-1", status: "completed"}] = completed.assignments
    assert [%{context_id: "ctx-1"}] = completed.context_objects

    assert {:ok, persisted} = Persistence.fetch_room_snapshot("room-state-1")
    assert persisted.status == "publication_ready"
    assert length(persisted.assignments) == 1
    assert length(persisted.contributions) == 1
    assert persisted.context_graph.outgoing["ctx-1"] == []
    assert hd(persisted.context_objects).uncertainty.rationale == nil
  end

  test "rejects contributions that violate room-owned participant scope" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-scope-1",
         snapshot:
           base_snapshot("room-scope-1")
           |> Map.put(:participants, [
             %{
               participant_id: "worker-01",
               participant_role: "analyst",
               participant_kind: "runtime",
               authority_level: "advisory",
               target_id: "target-worker-01",
               capability_id: "workspace.exec.session",
               metadata: %{}
             }
           ])
           |> Map.put(:context_config, %{
             participant_scopes: %{
               "worker-01" => %{
                 writable_types: ["note"],
                 writable_node_ids: :all,
                 reference_hop_limit: 2
               }
             }
           })}
      )

    assert {:error, {:scope_violation, %{kind: :drafted_object_type, object_type: "decision"}}} =
             RoomServer.record_contribution(room, %{
               "contribution" => %{
                 "room_id" => "room-scope-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "analyst",
                 "target_id" => "target-worker-01",
                 "capability_id" => "workspace.exec.session",
                 "contribution_type" => "reasoning",
                 "authority_level" => "advisory",
                 "summary" => "Out of scope decision.",
                 "context_objects" => [
                   %{
                     "object_type" => "decision",
                     "title" => "Do not allow"
                   }
                 ]
               }
             })

    assert {:ok, current} = RoomServer.snapshot(room)
    assert current.contributions == []
    assert Persistence.list_room_events("room-scope-1") == []
  end

  test "rejects contributions that use unknown relation names" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-invalid-relation-1",
         snapshot:
           base_snapshot("room-invalid-relation-1")
           |> Map.put(:participants, [
             %{
               participant_id: "human-01",
               participant_role: "reviewer",
               participant_kind: "human",
               authority_level: "binding",
               target_id: "target-human-01",
               capability_id: "human.chat",
               metadata: %{}
             }
           ])}
      )

    assert {:error, {:scope_violation, %{kind: :invalid_relation_type, relation: "derived_from"}}} =
             RoomServer.record_contribution(room, %{
               "contribution" => %{
                 "room_id" => "room-invalid-relation-1",
                 "participant_id" => "human-01",
                 "participant_role" => "reviewer",
                 "participant_kind" => "human",
                 "target_id" => "target-human-01",
                 "capability_id" => "human.chat",
                 "contribution_type" => "decision",
                 "authority_level" => "binding",
                 "summary" => "Use the wrong relation name.",
                 "context_objects" => [
                   %{
                     "object_type" => "decision",
                     "title" => "Bad relation",
                     "relations" => [
                       %{"relation" => "derived_from", "target_id" => "ctx-1"}
                     ]
                   }
                 ]
               }
             })

    assert {:ok, current} = RoomServer.snapshot(room)
    assert current.contributions == []
  end

  test "rejects contributions that omit relation target ids" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-missing-target-1",
         snapshot:
           base_snapshot("room-missing-target-1")
           |> Map.put(:participants, [
             %{
               participant_id: "human-01",
               participant_role: "reviewer",
               participant_kind: "human",
               authority_level: "binding",
               target_id: "target-human-01",
               capability_id: "human.chat",
               metadata: %{}
             }
           ])}
      )

    assert {:error, {:scope_violation, %{kind: :missing_relation_target, relation: "supports"}}} =
             RoomServer.record_contribution(room, %{
               "contribution" => %{
                 "room_id" => "room-missing-target-1",
                 "participant_id" => "human-01",
                 "participant_role" => "reviewer",
                 "participant_kind" => "human",
                 "target_id" => "target-human-01",
                 "capability_id" => "human.chat",
                 "contribution_type" => "reasoning",
                 "authority_level" => "binding",
                 "summary" => "Missing relation target.",
                 "context_objects" => [
                   %{
                     "object_type" => "evidence",
                     "title" => "Bad evidence",
                     "relations" => [
                       %{"relation" => "supports", "target_id" => nil}
                     ]
                   }
                 ]
               }
             })

    assert {:ok, current} = RoomServer.snapshot(room)
    assert current.contributions == []
  end

  test "projects stale annotations after accepted appends without persisting derived graph events" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-effects-1",
         snapshot:
           base_snapshot("room-effects-1")
           |> Map.put(:context_objects, [
             %{
               context_id: "ctx-ancestor",
               object_type: "fact",
               title: "Original fact",
               body: nil,
               data: %{},
               authored_by: %{participant_id: "worker-00", capability_id: "cap-a"},
               provenance: %{authority_level: "binding"},
               scope: %{read: ["room"], write: ["author"]},
               uncertainty: %{status: "accepted", confidence: 1.0, rationale: nil},
               relations: [],
               inserted_at: DateTime.utc_now()
             },
             %{
               context_id: "ctx-child",
               object_type: "note",
               title: "Downstream note",
               body: nil,
               data: %{},
               authored_by: %{participant_id: "worker-00", capability_id: "cap-a"},
               provenance: %{authority_level: "binding"},
               scope: %{read: ["room"], write: ["author"]},
               uncertainty: %{status: "accepted", confidence: 1.0, rationale: nil},
               relations: [%{relation: "derives_from", target_id: "ctx-ancestor"}],
               inserted_at: DateTime.utc_now()
             },
             %{
               context_id: "ctx-decision",
               object_type: "decision",
               title: "Existing decision",
               body: nil,
               data: %{},
               authored_by: %{participant_id: "worker-00", capability_id: "cap-a"},
               provenance: %{authority_level: "binding"},
               scope: %{read: ["room"], write: ["author"]},
               uncertainty: %{status: "accepted", confidence: 1.0, rationale: nil},
               relations: [],
               inserted_at: DateTime.utc_now()
             }
           ])
           |> Map.put(:next_context_seq, 1)}
      )

    assert {:ok, updated} =
             RoomServer.record_contribution(room, %{
               "contribution" => %{
                 "room_id" => "room-effects-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "analyst",
                 "participant_kind" => "runtime",
                 "contribution_type" => "reasoning",
                 "authority_level" => "advisory",
                 "summary" => "Supersede and contradict.",
                 "context_objects" => [
                   %{
                     "object_type" => "fact",
                     "title" => "Replacement fact",
                     "relations" => [
                       %{"relation" => "supersedes", "target_id" => "ctx-ancestor"}
                     ]
                   },
                   %{
                     "object_type" => "note",
                     "title" => "Counterpoint",
                     "relations" => [
                       %{"relation" => "contradicts", "target_id" => "ctx-decision"}
                     ]
                   }
                 ]
               }
             })

    assert updated.context_annotations["ctx-child"] == %{
             stale_ancestor: true,
             stale_due_to_ids: ["ctx-ancestor"]
           }

    event_types = Persistence.list_room_events("room-effects-1") |> Enum.map(& &1.type)

    assert event_types == [:contribution_submitted]
  end

  test "treats repeated assignment contributions from the same participant as idempotent" do
    room =
      start_supervised!(
        {RoomServer,
         room_id: "room-idempotent-1",
         snapshot:
           base_snapshot("room-idempotent-1")
           |> Map.put(:participants, [
             %{
               participant_id: "worker-01",
               participant_role: "analyst",
               participant_kind: "runtime",
               authority_level: "advisory",
               target_id: "target-worker-01",
               capability_id: "workspace.exec.session",
               metadata: %{}
             }
           ])}
      )

    assert {:ok, _opened} =
             RoomServer.open_assignment(room, %{
               "assignment" => %{
                 "assignment_id" => "asn-1",
                 "room_id" => "room-idempotent-1",
                 "participant_id" => "worker-01",
                 "participant_role" => "analyst",
                 "target_id" => "target-worker-01",
                 "capability_id" => "workspace.exec.session",
                 "phase" => "analysis",
                 "objective" => "Analyze the brief.",
                 "contribution_contract" => %{"allowed_contribution_types" => ["reasoning"]},
                 "context_view" => %{"brief" => "Design a substrate.", "context_objects" => []},
                 "status" => "running",
                 "opened_at" => DateTime.utc_now()
               }
             })

    payload = %{
      "contribution" => %{
        "contribution_id" => "contrib-idempotent-1",
        "room_id" => "room-idempotent-1",
        "assignment_id" => "asn-1",
        "participant_id" => "worker-01",
        "participant_role" => "analyst",
        "target_id" => "target-worker-01",
        "capability_id" => "workspace.exec.session",
        "contribution_type" => "reasoning",
        "authority_level" => "advisory",
        "summary" => "Added a belief once.",
        "consumed_context_ids" => [],
        "context_objects" => [
          %{
            "object_type" => "belief",
            "title" => "Shared state",
            "body" => "Server-owned state."
          }
        ],
        "artifacts" => [],
        "events" => [],
        "tool_events" => [],
        "approvals" => [],
        "execution" => %{"status" => "completed"},
        "status" => "completed",
        "schema_version" => "jido_hive/contribution.submit.v1"
      }
    }

    assert {:ok, first} = RoomServer.record_contribution(room, payload)
    assert {:ok, second} = RoomServer.record_contribution(room, payload)

    assert length(first.contributions) == 1
    assert length(second.contributions) == 1
    assert length(second.context_objects) == 1

    assert Enum.map(Persistence.list_room_events("room-idempotent-1"), & &1.type) == [
             :assignment_created,
             :contribution_submitted,
             :assignment_completed
           ]
  end

  defp base_snapshot(room_id) do
    %{
      room_id: room_id,
      session_id: "session-#{room_id}",
      brief: "Design a participation substrate.",
      rules: ["Return structured contributions only."],
      status: "idle",
      participants: [],
      current_assignment: %{},
      assignments: [],
      context_objects: [],
      contributions: [],
      context_graph: %{outgoing: %{}, incoming: %{}},
      context_annotations: %{},
      context_config: %{participant_scopes: %{}},
      dispatch_policy_id: "round_robin/v2",
      dispatch_policy_config: %{},
      dispatch_state: %{applied_event_ids: [], completed_slots: 0, total_slots: 1},
      next_context_seq: 1,
      next_assignment_seq: 1,
      next_contribution_seq: 1
    }
  end
end
