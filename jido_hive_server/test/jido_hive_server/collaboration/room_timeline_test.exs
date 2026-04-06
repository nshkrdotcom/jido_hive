defmodule JidoHiveServer.Collaboration.RoomTimelineTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.RoomTimeline
  alias JidoHiveServer.Collaboration.Schema.RoomEvent

  test "projects room events into canonical timeline entries" do
    recorded_at = DateTime.utc_now()

    {:ok, created} =
      RoomEvent.new(%{
        event_id: "evt-room-created-1",
        room_id: "room-1",
        type: :room_created,
        payload: %{brief: "Design a generalized substrate."},
        recorded_at: recorded_at
      })

    {:ok, opened} =
      RoomEvent.new(%{
        event_id: "evt-assignment-opened-1",
        room_id: "room-1",
        type: :assignment_opened,
        payload: %{
          assignment: %{
            assignment_id: "asn-1",
            phase: "analysis",
            participant_id: "worker-01",
            participant_role: "analyst",
            target_id: "target-worker-01",
            objective: "Analyze the brief."
          }
        },
        recorded_at: recorded_at
      })

    {:ok, completed} =
      RoomEvent.new(%{
        event_id: "evt-contribution-recorded-1",
        room_id: "room-1",
        type: :contribution_recorded,
        payload: %{
          contribution: %{
            contribution_id: "contrib-1",
            assignment_id: "asn-1",
            participant_id: "worker-01",
            participant_role: "analyst",
            contribution_type: "reasoning",
            summary: "analysis completed",
            status: "completed"
          }
        },
        recorded_at: recorded_at
      })

    assert [
             %{kind: "room.created", room_id: "room-1"},
             %{kind: "assignment.started", phase: "analysis", assignment_id: "asn-1"},
             %{kind: "contribution.recorded", status: "completed", body: "analysis completed"}
           ] = RoomTimeline.project([created, opened, completed])
  end
end
