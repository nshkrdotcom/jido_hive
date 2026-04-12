defmodule JidoHiveServer.Collaboration.EventReducerTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.EventReducer
  alias JidoHiveServer.Collaboration.Schema.{Room, RoomEvent, RoomSnapshot}

  test "assignment_created tracks the assignment and active dispatch ids" do
    snapshot = snapshot()

    {:ok, event} =
      RoomEvent.new(%{
        id: "evt-1",
        room_id: "room-1",
        sequence: 1,
        type: :assignment_created,
        data: %{
          "assignment" => %{
            "id" => "asg-1",
            "room_id" => "room-1",
            "participant_id" => "participant-1",
            "payload" => %{"objective" => "Analyze"},
            "status" => "pending",
            "meta" => %{}
          }
        }
      })

    updated = EventReducer.apply_event(snapshot, event)

    assert [assignment] = updated.assignments
    assert assignment.id == "asg-1"
    assert updated.dispatch.active_assignment_ids == ["asg-1"]
    assert updated.dispatch.completed_assignment_ids == []
    assert updated.clocks.next_assignment_seq == 2
    assert updated.clocks.next_event_sequence == 2
  end

  test "contribution_submitted appends contributions without deriving graph state" do
    snapshot = snapshot()

    {:ok, event} =
      RoomEvent.new(%{
        id: "evt-2",
        room_id: "room-1",
        sequence: 2,
        type: :contribution_submitted,
        data: %{
          "contribution" => %{
            "id" => "ctrb-1",
            "room_id" => "room-1",
            "participant_id" => "participant-1",
            "assignment_id" => "asg-1",
            "kind" => "reasoning",
            "payload" => %{"summary" => "Shared an analysis"},
            "meta" => %{"trace" => %{"provider" => "codex"}}
          }
        }
      })

    updated = EventReducer.apply_event(snapshot, event)

    assert [contribution] = updated.contributions
    assert contribution.id == "ctrb-1"
    assert contribution.payload["summary"] == "Shared an analysis"
    assert updated.clocks.next_contribution_seq == 2
    assert updated.clocks.next_event_sequence == 3
  end

  test "assignment_completed moves the assignment into the completed set" do
    snapshot =
      snapshot(%{
        assignments: [
          %{
            id: "asg-1",
            room_id: "room-1",
            participant_id: "participant-1",
            payload: %{},
            status: "active",
            deadline: nil,
            inserted_at: DateTime.utc_now(),
            meta: %{}
          }
        ],
        dispatch: %{
          policy_id: "round_robin",
          policy_state: %{},
          active_assignment_ids: ["asg-1"],
          completed_assignment_ids: []
        }
      })

    {:ok, event} =
      RoomEvent.new(%{
        id: "evt-3",
        room_id: "room-1",
        sequence: 3,
        type: :assignment_completed,
        data: %{"assignment_id" => "asg-1"}
      })

    updated = EventReducer.apply_event(snapshot, event)

    assert [assignment] = updated.assignments
    assert assignment.status == "completed"
    assert updated.dispatch.active_assignment_ids == []
    assert updated.dispatch.completed_assignment_ids == ["asg-1"]
    assert updated.clocks.next_event_sequence == 4
  end

  test "room phase and status changes are explicit" do
    snapshot = snapshot()

    {:ok, status_event} =
      RoomEvent.new(%{
        id: "evt-4",
        room_id: "room-1",
        sequence: 4,
        type: :room_status_changed,
        data: %{"status" => "active", "inserted_at" => DateTime.utc_now()}
      })

    {:ok, phase_event} =
      RoomEvent.new(%{
        id: "evt-5",
        room_id: "room-1",
        sequence: 5,
        type: :room_phase_changed,
        data: %{"phase" => "analysis", "inserted_at" => DateTime.utc_now()}
      })

    updated =
      snapshot
      |> EventReducer.apply_event(status_event)
      |> EventReducer.apply_event(phase_event)

    assert updated.room.status == "active"
    assert updated.room.phase == "analysis"
    assert updated.clocks.next_event_sequence == 6
  end

  defp snapshot(overrides \\ %{}) do
    {:ok, room} =
      Room.new(%{
        id: "room-1",
        name: "Canonical room",
        status: "waiting",
        config: %{}
      })

    RoomSnapshot.initial(room, "round_robin", %{})
    |> Map.merge(overrides)
  end
end
