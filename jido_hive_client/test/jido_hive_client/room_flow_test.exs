defmodule JidoHiveClient.RoomFlowTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.RoomFlow

  test "keeps a chat submit pending until the submitted text is visible in the room snapshot" do
    flow =
      "room-1"
      |> RoomFlow.new()
      |> RoomFlow.submit_accepted(%{
        "operation_id" => "room_submit-1",
        "status" => "accepted",
        "text" => "Hello room"
      })

    assert RoomFlow.pending_submit?(flow)

    assert {:info, "Chat submit accepted; waiting for server confirmation. op=room_submit-1"} =
             RoomFlow.status(flow)

    flow =
      RoomFlow.ingest_snapshot(flow, %{
        "room_id" => "room-1",
        "status" => "idle",
        "timeline" => [],
        "context_objects" => [],
        "operations" => [
          %{
            "operation_id" => "room_submit-1",
            "kind" => "submit_chat",
            "status" => "completed",
            "text" => "Hello room"
          }
        ]
      })

    assert RoomFlow.pending_submit?(flow)

    flow =
      RoomFlow.ingest_snapshot(flow, %{
        "room_id" => "room-1",
        "status" => "idle",
        "timeline" => [
          %{
            "kind" => "contribution.submitted",
            "body" => "Hello room"
          }
        ],
        "context_objects" => [
          %{
            "object_type" => "message",
            "body" => "Hello room"
          }
        ],
        "operations" => [
          %{
            "operation_id" => "room_submit-1",
            "kind" => "submit_chat",
            "status" => "completed",
            "text" => "Hello room"
          }
        ]
      })

    refute RoomFlow.pending_submit?(flow)
    assert {:info, "Submitted chat message"} = RoomFlow.status(flow)
  end

  test "derives room run status from the latest room run operation" do
    flow =
      "room-1"
      |> RoomFlow.new()
      |> RoomFlow.run_accepted(%{
        "operation_id" => "room_run-1",
        "client_operation_id" => "room_run-client-1",
        "status" => "accepted"
      })

    assert RoomFlow.pending_run?(flow)

    flow =
      RoomFlow.ingest_snapshot(flow, %{
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

    assert {:info, "Room run running; server_op=room_run-1 client_op=room_run-client-1"} =
             RoomFlow.status(flow)

    flow =
      RoomFlow.ingest_snapshot(flow, %{
        "room_id" => "room-1",
        "status" => "completed",
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

    refute RoomFlow.pending_run?(flow)
    assert {:info, "Room run completed"} = RoomFlow.status(flow)
  end
end
