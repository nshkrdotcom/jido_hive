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
        event_id: "evt-turn-opened-1",
        room_id: "room-1",
        type: :turn_opened,
        payload: %{
          job_id: "job-1",
          phase: "proposal",
          participant_id: "worker-01",
          participant_role: "proposer",
          target_id: "target-worker-01"
        },
        recorded_at: recorded_at
      })

    {:ok, completed} =
      RoomEvent.new(%{
        event_id: "evt-turn-completed-1",
        room_id: "room-1",
        type: :turn_completed,
        payload: %{
          job_id: "job-1",
          participant_id: "worker-01",
          participant_role: "proposer",
          status: "completed",
          summary: "proposal completed"
        },
        recorded_at: recorded_at
      })

    assert [
             %{
               kind: "room.created",
               room_id: "room-1",
               event_id: "evt-room-created-1",
               cursor: "evt-room-created-1",
               schema_version: "jido_hive/room_timeline_entry.v1",
               timestamp: _timestamp
             },
             %{
               kind: "turn.dispatched",
               phase: "proposal",
               job_id: "job-1",
               participant_id: "worker-01"
             },
             %{
               kind: "turn.completed",
               status: "completed",
               body: "proposal completed"
             }
           ] = RoomTimeline.project([created, opened, completed])
  end
end
