defmodule JidoHiveServer.Collaboration.EventReducerTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.EventReducer
  alias JidoHiveServer.Collaboration.Schema.RoomEvent

  test "assignment_opened updates current_assignment and assignments" do
    {:ok, event} =
      RoomEvent.new(%{
        event_id: "evt-open-1",
        room_id: "room-1",
        type: :assignment_opened,
        payload: %{
          assignment: %{
            assignment_id: "asn-1",
            room_id: "room-1",
            participant_id: "worker-01",
            participant_role: "analyst",
            target_id: "target-worker-01",
            capability_id: "codex.exec.session",
            phase: "analysis",
            objective: "Analyze the brief.",
            contribution_contract: %{"allowed_contribution_types" => ["reasoning"]},
            context_view: %{"brief" => "Design a substrate.", "context_objects" => []},
            status: "running",
            opened_at: DateTime.utc_now()
          }
        },
        recorded_at: DateTime.utc_now()
      })

    updated = EventReducer.apply_event(snapshot(), event)

    assert updated.current_assignment.assignment_id == "asn-1"
    assert List.last(updated.assignments).assignment_id == "asn-1"
    assert updated.status == "running"
    assert updated.dispatch_state.completed_slots == 0
  end

  test "contribution_recorded appends contributions and context objects" do
    opened_at = DateTime.utc_now()

    {:ok, event} =
      RoomEvent.new(%{
        event_id: "evt-contrib-1",
        room_id: "room-1",
        type: :contribution_recorded,
        payload: %{
          contribution: %{
            contribution_id: "contrib-1",
            room_id: "room-1",
            assignment_id: "asn-1",
            participant_id: "worker-01",
            participant_role: "analyst",
            target_id: "target-worker-01",
            capability_id: "codex.exec.session",
            contribution_type: "reasoning",
            authority_level: "advisory",
            summary: "Added a substrate belief.",
            consumed_context_ids: [],
            context_objects: [
              %{
                object_type: "belief",
                title: "Shared state",
                body: "The server should own room state.",
                data: %{},
                scope: %{"read" => ["room"], "write" => ["author"]},
                uncertainty: %{"status" => "provisional", "confidence" => 0.8},
                relations: [%{relation: "derives_from", target_id: "ctx-existing"}]
              }
            ],
            artifacts: [],
            events: [],
            tool_events: [],
            approvals: [],
            execution: %{"status" => "completed"},
            status: "completed",
            schema_version: "jido_hive/contribution.submit.v1"
          }
        },
        recorded_at: DateTime.utc_now()
      })

    updated =
      snapshot(%{
        status: "running",
        current_assignment: %{
          assignment_id: "asn-1",
          room_id: "room-1",
          participant_id: "worker-01",
          participant_role: "analyst",
          target_id: "target-worker-01",
          capability_id: "codex.exec.session",
          phase: "analysis",
          objective: "Analyze the brief.",
          contribution_contract: %{"allowed_contribution_types" => ["reasoning"]},
          context_view: %{"brief" => "Design a substrate.", "context_objects" => []},
          status: "running",
          opened_at: opened_at
        },
        assignments: [
          %{
            assignment_id: "asn-1",
            room_id: "room-1",
            participant_id: "worker-01",
            participant_role: "analyst",
            target_id: "target-worker-01",
            capability_id: "codex.exec.session",
            phase: "analysis",
            objective: "Analyze the brief.",
            contribution_contract: %{"allowed_contribution_types" => ["reasoning"]},
            context_view: %{"brief" => "Design a substrate.", "context_objects" => []},
            status: "running",
            opened_at: opened_at
          }
        ],
        context_objects: [
          %{
            context_id: "ctx-existing",
            object_type: "fact",
            title: "Seed fact",
            body: "Earlier fact.",
            data: %{},
            authored_by: %{participant_id: "worker-00"},
            provenance: %{},
            scope: %{read: ["room"], write: ["author"]},
            uncertainty: %{status: "accepted", confidence: 1.0, rationale: nil},
            relations: [],
            inserted_at: opened_at
          }
        ],
        dispatch_state: %{applied_event_ids: [], completed_slots: 0, total_slots: 1}
      })
      |> EventReducer.apply_event(event)

    assert updated.current_assignment == %{}
    assert updated.dispatch_state.completed_slots == 1
    assert updated.status == "publication_ready"
    assert [%{contribution_id: "contrib-1"}] = updated.contributions

    assert [
             %{context_id: "ctx-existing", object_type: "fact"},
             %{context_id: "ctx-1", object_type: "belief"}
           ] = updated.context_objects

    assert [%{assignment_id: "asn-1", status: "completed"}] = updated.assignments

    assert updated.context_graph.outgoing["ctx-1"] |> Enum.map(&{&1.type, &1.to_id}) == [
             {:derives_from, "ctx-existing"}
           ]
  end

  test "assignment_abandoned marks the assignment as abandoned and advances dispatch state" do
    {:ok, event} =
      RoomEvent.new(%{
        event_id: "evt-abandon-1",
        room_id: "room-1",
        type: :assignment_abandoned,
        payload: %{
          assignment_id: "asn-1",
          reason: "assignment timed out"
        },
        recorded_at: DateTime.utc_now()
      })

    updated =
      snapshot(%{
        status: "running",
        current_assignment: %{assignment_id: "asn-1", participant_id: "worker-01"},
        assignments: [%{assignment_id: "asn-1", participant_id: "worker-01", status: "running"}],
        dispatch_state: %{applied_event_ids: [], completed_slots: 0, total_slots: 2}
      })
      |> EventReducer.apply_event(event)

    assert updated.current_assignment == %{}
    assert updated.dispatch_state.completed_slots == 1
    assert [%{assignment_id: "asn-1", status: "abandoned"}] = updated.assignments
  end

  defp snapshot(overrides \\ %{}) do
    Map.merge(
      %{
        room_id: "room-1",
        session_id: "session-1",
        brief: "Design a participation substrate.",
        rules: [],
        status: "idle",
        participants: [],
        current_assignment: %{},
        assignments: [],
        context_objects: [],
        contributions: [],
        context_graph: %{outgoing: %{}, incoming: %{}},
        context_annotations: %{},
        dispatch_policy_id: "round_robin/v2",
        dispatch_policy_config: %{},
        dispatch_state: %{applied_event_ids: [], completed_slots: 0, total_slots: 1},
        next_context_seq: 1,
        next_assignment_seq: 1,
        next_contribution_seq: 1
      },
      overrides
    )
  end
end
