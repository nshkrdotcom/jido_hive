defmodule JidoHiveServer.Collaboration.Schema.RoomEventTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.Schema.RoomEvent

  test "builds a typed room event when required fields are present" do
    recorded_at = DateTime.utc_now()

    assert {:ok, %RoomEvent{} = event} =
             RoomEvent.new(%{
               event_id: "evt-1",
               room_id: "room-1",
               type: :room_created,
               payload: %{brief: "Design a workflow substrate."},
               recorded_at: recorded_at
             })

    assert event.event_id == "evt-1"
    assert event.room_id == "room-1"
    assert event.type == :room_created
    assert event.payload == %{brief: "Design a workflow substrate."}
    assert event.recorded_at == recorded_at
  end

  test "rejects missing required fields" do
    assert {:error, {:missing_field, :type}} =
             RoomEvent.new(%{
               event_id: "evt-1",
               room_id: "room-1",
               payload: %{},
               recorded_at: DateTime.utc_now()
             })
  end
end
