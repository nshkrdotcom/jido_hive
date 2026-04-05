defmodule JidoHiveServer.Persistence.RoomEventsTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias JidoHiveServer.Collaboration.Schema.RoomEvent
  alias JidoHiveServer.Persistence

  test "appends and lists room events in insertion order" do
    recorded_at = DateTime.utc_now()

    {:ok, first} =
      RoomEvent.new(%{
        event_id: "evt-room-1",
        room_id: "room-1",
        type: :room_created,
        payload: %{brief: "First event"},
        recorded_at: recorded_at
      })

    {:ok, second} =
      RoomEvent.new(%{
        event_id: "evt-room-2",
        room_id: "room-1",
        type: :turn_opened,
        payload: %{job_id: "job-1"},
        recorded_at: recorded_at
      })

    assert :ok = Persistence.append_room_events("room-1", [first, second])

    assert [listed_first, listed_second] = Persistence.list_room_events("room-1")
    assert listed_first.event_id == "evt-room-1"
    assert listed_first.type == :room_created
    assert listed_second.event_id == "evt-room-2"
    assert listed_second.type == :turn_opened
  end
end
