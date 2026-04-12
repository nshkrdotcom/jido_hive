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
           "id" => room_id,
           "name" => "Wrapped room",
           "status" => "running",
           "participants" => [],
           "context_objects" => [
             %{
               "context_id" => "ctx-1",
               "object_type" => "message",
               "title" => "alice said",
               "body" => "hello"
             }
           ]
         }
       }}
    end

    @impl true
    def list_events(_opts, _room_id, _query_opts) do
      {:ok,
       %{
         entries: [
           %{
             "entry_id" => "evt-1",
             "cursor" => "evt-1",
             "event_id" => "evt-1",
             "kind" => "assignment.created",
             "status" => "running",
             "metadata" => %{"phase" => "analysis"}
           }
         ],
         next_cursor: "evt-1"
       }}
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

    assert snapshot["id"] == "room-embedded-wrap-1"
    assert snapshot["name"] == "Wrapped room"
    assert snapshot["status"] == "running"

    assert snapshot["timeline"] == [
             %{
               "entry_id" => "evt-1",
               "cursor" => "evt-1",
               "event_id" => "evt-1",
               "kind" => "assignment.created",
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
