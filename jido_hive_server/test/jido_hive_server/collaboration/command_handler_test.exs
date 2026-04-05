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
    assert event.payload.brief == "Design a generalized substrate."
  end

  test "maps failed turn results to turn_failed events" do
    {:ok, command} =
      RoomCommand.new(%{
        command_id: "cmd-result-1",
        room_id: "room-1",
        type: :apply_turn_result,
        payload: %{
          job_id: "job-1",
          participant_id: "worker-01",
          participant_role: "worker",
          status: "failed",
          summary: "execution failed",
          actions: [],
          tool_events: [],
          events: [],
          approvals: [],
          artifacts: [],
          execution: %{"status" => "failed"}
        },
        issued_at: DateTime.utc_now()
      })

    assert {:ok, [%RoomEvent{} = event]} = CommandHandler.handle(command)
    assert event.type == :turn_failed
    assert event.payload.status == "failed"
  end
end
