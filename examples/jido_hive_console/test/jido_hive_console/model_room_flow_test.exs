defmodule JidoHiveConsole.ModelRoomFlowTest do
  use ExUnit.Case, async: true

  alias JidoHiveConsole.{App, Model}

  test "model derives pending submit and submitted status from the shared room flow" do
    state =
      Model.new(
        active_screen: :room,
        room_id: "room-1",
        snapshot: %{"timeline" => [], "context_objects" => [], "operations" => []}
      )
      |> Model.track_room_submit(%{
        "operation_id" => "room_submit-1",
        "status" => "accepted",
        "text" => "Hello room"
      })

    assert state.pending_room_submit == %{
             room_id: "room-1",
             text: "Hello room",
             operation_id: "room_submit-1"
           }

    assert state.status_line ==
             "Chat submit accepted; waiting for server confirmation. op=room_submit-1"

    next_state =
      Model.apply_snapshot(state, %{
        "room_id" => "room-1",
        "status" => "idle",
        "timeline" => [%{"kind" => "contribution.recorded", "body" => "Hello room"}],
        "context_objects" => [%{"object_type" => "message", "body" => "Hello room"}],
        "operations" => [
          %{
            "operation_id" => "room_submit-1",
            "kind" => "submit_chat",
            "status" => "completed",
            "text" => "Hello room"
          }
        ]
      })

    assert next_state.pending_room_submit == nil
    assert next_state.status_line == "Submitted chat message"
  end

  test "model derives pending room runs from the shared room flow" do
    state =
      Model.new(
        active_screen: :room,
        room_id: "room-1",
        snapshot: %{"timeline" => [], "context_objects" => [], "operations" => []}
      )
      |> Model.track_room_run(%{
        "operation_id" => "room_run-1",
        "client_operation_id" => "room_run-client-1",
        "status" => "accepted"
      })

    assert state.pending_room_run == %{
             room_id: "room-1",
             operation_id: "room_run-1",
             client_operation_id: "room_run-client-1"
           }

    running_state =
      Model.apply_snapshot(state, %{
        "room_id" => "room-1",
        "status" => "running",
        "timeline" => [],
        "context_objects" => [],
        "operations" => [
          %{
            "operation_id" => "room_run-1",
            "client_operation_id" => "room_run-client-1",
            "kind" => "room_run",
            "status" => "running"
          }
        ]
      })

    assert running_state.status_line ==
             "Room run running; server_op=room_run-1 client_op=room_run-client-1"

    completed_state =
      Model.apply_snapshot(running_state, %{
        "room_id" => "room-1",
        "status" => "publication_ready",
        "timeline" => [],
        "context_objects" => [],
        "operations" => [
          %{
            "operation_id" => "room_run-1",
            "client_operation_id" => "room_run-client-1",
            "kind" => "room_run",
            "status" => "completed"
          }
        ]
      })

    assert completed_state.pending_room_run == nil
    assert completed_state.status_line == "Room run completed"
  end

  test "room poll no longer injects ad hoc run-status or submit-refresh effects" do
    state =
      Model.new(
        active_screen: :room,
        room_id: "room-1",
        poll_interval_ms: 1_000,
        snapshot: %{"timeline" => [], "context_objects" => [], "operations" => []}
      )
      |> Model.track_room_submit(%{
        "operation_id" => "room_submit-1",
        "status" => "accepted",
        "text" => "Hello room"
      })
      |> Model.track_room_run(%{
        "operation_id" => "room_run-1",
        "client_operation_id" => "room_run-client-1",
        "status" => "running"
      })

    assert {next_state, effects} = App.update(:poll, state)
    assert next_state.pending_room_submit != nil
    assert next_state.pending_room_run != nil
    assert effects == [{:timer, 1_000, :poll}]
  end
end
