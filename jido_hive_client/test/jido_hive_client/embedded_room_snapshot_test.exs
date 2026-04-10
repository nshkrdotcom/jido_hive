defmodule JidoHiveClient.EmbeddedRoomSnapshotTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Embedded

  defmodule WrappedRoomApiStub do
    @behaviour JidoHiveClient.Boundary.RoomApi

    @impl true
    def fetch_room(_opts, room_id) do
      {:ok,
       %{
         "data" => %{
           "room_id" => room_id,
           "status" => "running",
           "dispatch_state" => %{"completed_slots" => 3, "total_slots" => 6},
           "participants" => []
         }
       }}
    end

    @impl true
    def fetch_sync(_opts, room_id, _query_opts) do
      {:ok,
       %{
         room_snapshot: %{
           "data" => %{
             "room_id" => room_id,
             "status" => "running",
             "dispatch_state" => %{"completed_slots" => 3, "total_slots" => 6},
             "participants" => []
           }
         },
         entries: [
           %{
             "entry_id" => "evt-1",
             "cursor" => "evt-1",
             "event_id" => "evt-1",
             "kind" => "assignment.started",
             "status" => "running",
             "metadata" => %{"phase" => "analysis"}
           }
         ],
         next_cursor: "evt-1",
         context_objects: [
           %{
             "context_id" => "ctx-1",
             "object_type" => "message",
             "title" => "alice said",
             "body" => "hello"
           }
         ],
         operations: []
       }}
    end

    @impl true
    def fetch_timeline(_opts, _room_id, _query_opts) do
      {:ok,
       %{
         entries: [
           %{
             "entry_id" => "evt-1",
             "cursor" => "evt-1",
             "event_id" => "evt-1",
             "kind" => "assignment.started",
             "status" => "running",
             "metadata" => %{"phase" => "analysis"}
           }
         ],
         next_cursor: "evt-1"
       }}
    end

    @impl true
    def fetch_context_objects(_opts, _room_id) do
      {:ok,
       [
         %{
           "context_id" => "ctx-1",
           "object_type" => "message",
           "title" => "alice said",
           "body" => "hello"
         }
       ]}
    end

    @impl true
    def submit_contribution(_opts, _room_id, _payload) do
      {:ok, %{"data" => %{}}}
    end
  end

  test "normalizes wrapped room snapshots into canonical top-level room fields" do
    {:ok, embedded} =
      start_supervised(
        {Embedded,
         room_id: "room-embedded-wrap-1",
         participant_id: "alice",
         participant_role: "coordinator",
         participant_kind: "human",
         room_api: {WrappedRoomApiStub, []},
         poll_interval_ms: 10_000}
      )

    assert :ok = Embedded.subscribe(embedded)
    assert {:ok, snapshot} = Embedded.refresh(embedded)

    assert snapshot["room_id"] == "room-embedded-wrap-1"
    assert snapshot["status"] == "running"
    assert snapshot["dispatch_state"] == %{"completed_slots" => 3, "total_slots" => 6}

    assert snapshot["timeline"] == [
             %{
               "entry_id" => "evt-1",
               "cursor" => "evt-1",
               "event_id" => "evt-1",
               "kind" => "assignment.started",
               "status" => "running",
               "metadata" => %{"phase" => "analysis"}
             }
           ]

    assert snapshot["context_objects"] == [
             %{
               "context_id" => "ctx-1",
               "object_type" => "message",
               "title" => "alice said",
               "body" => "hello"
             }
           ]
  end
end
