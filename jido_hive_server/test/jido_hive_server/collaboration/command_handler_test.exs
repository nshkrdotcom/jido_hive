defmodule JidoHiveServer.Collaboration.CommandHandlerTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.CommandHandler
  alias JidoHiveServer.Collaboration.Schema.{RoomCommand, RoomEvent}

  test "builds a room_created event from a create_room command" do
    {:ok, command} =
      RoomCommand.new(%{
        command_id: "cmd-create-1",
        room_id: "room-1",
        type: :create_room,
        payload: %{brief: "Design a generalized substrate."},
        issued_at: DateTime.utc_now()
      })

    assert {:ok, [%RoomEvent{} = event]} = CommandHandler.handle(command)
    assert event.type == :room_created
    assert event.room_id == "room-1"
    assert event.causation_id == "cmd-create-1"
  end

  test "maps record_contribution commands to contribution_submitted events" do
    {:ok, command} =
      RoomCommand.new(%{
        command_id: "cmd-contrib-1",
        room_id: "room-1",
        type: :record_contribution,
        payload: %{summary: "Added a contribution."},
        issued_at: DateTime.utc_now()
      })

    assert {:ok, [%RoomEvent{} = event]} = CommandHandler.handle(command)
    assert event.type == :contribution_submitted
    assert event.payload.summary == "Added a contribution."
  end
end
