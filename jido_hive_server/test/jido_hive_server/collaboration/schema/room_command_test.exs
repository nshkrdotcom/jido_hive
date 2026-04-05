defmodule JidoHiveServer.Collaboration.Schema.RoomCommandTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.Schema.RoomCommand

  test "builds a typed room command when required fields are present" do
    issued_at = DateTime.utc_now()

    assert {:ok, %RoomCommand{} = command} =
             RoomCommand.new(%{
               command_id: "cmd-1",
               room_id: "room-1",
               type: :create_room,
               payload: %{brief: "Design a workflow substrate."},
               issued_at: issued_at
             })

    assert command.command_id == "cmd-1"
    assert command.room_id == "room-1"
    assert command.type == :create_room
    assert command.payload == %{brief: "Design a workflow substrate."}
    assert command.issued_at == issued_at
  end

  test "rejects missing required fields" do
    assert {:error, {:missing_field, :room_id}} =
             RoomCommand.new(%{
               command_id: "cmd-1",
               type: :create_room,
               payload: %{},
               issued_at: DateTime.utc_now()
             })
  end
end
