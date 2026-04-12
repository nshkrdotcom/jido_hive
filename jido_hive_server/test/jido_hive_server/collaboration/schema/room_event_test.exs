defmodule JidoHiveServer.Collaboration.Schema.RoomEventTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.Schema.RoomEvent

  test "builds a typed room event when required fields are present" do
    recorded_at = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, %RoomEvent{} = event} =
             RoomEvent.new(%{
               id: "evt-1",
               room_id: "room-1",
               sequence: 1,
               type: :room_created,
               data: %{"room" => %{"id" => "room-1", "name" => "Substrate"}},
               inserted_at: recorded_at
             })

    assert event.id == "evt-1"
    assert event.room_id == "room-1"
    assert event.sequence == 1
    assert event.type == :room_created
    assert event.data["room"]["name"] == "Substrate"
    assert event.inserted_at == recorded_at
  end

  test "rejects missing canonical fields" do
    assert {:error, {:missing_field, "sequence"}} =
             RoomEvent.new(%{
               id: "evt-1",
               room_id: "room-1",
               type: :room_created,
               data: %{}
             })
  end
end
