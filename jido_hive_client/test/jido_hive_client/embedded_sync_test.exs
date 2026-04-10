defmodule JidoHiveClient.EmbeddedSyncTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Embedded

  defmodule SyncOnlyRoomApiStub do
    def start_link do
      Agent.start_link(fn -> %{calls: 0} end)
    end

    def fetch_sync(opts, room_id, query_opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      server = Keyword.fetch!(opts, :server)

      call_number =
        Agent.get_and_update(server, fn state ->
          next = state.calls + 1
          {next, %{state | calls: next}}
        end)

      send(test_pid, {:fetch_sync, room_id, query_opts, call_number})

      {:ok,
       %{
         room_snapshot: %{
           "room_id" => room_id,
           "status" => "running",
           "dispatch_state" => %{"completed_slots" => 1, "total_slots" => 2},
           "participants" => []
         },
         entries: [
           %{
             "event_id" => "evt-1",
             "cursor" => "evt-1",
             "kind" => "contribution.recorded",
             "body" => "Hello sync"
           }
         ],
         next_cursor: "evt-1",
         context_objects: [
           %{
             "context_id" => "ctx-1",
             "object_type" => "message",
             "body" => "Hello sync"
           }
         ],
         operations: [
           %{
             "operation_id" => "room_run-1",
             "client_operation_id" => "room_run-client-1",
             "kind" => "room_run",
             "status" => "running"
           }
         ]
       }}
    end

    def fetch_room(_opts, _room_id), do: flunk("fetch_room should not be called")

    def fetch_timeline(_opts, _room_id, _query_opts),
      do: flunk("fetch_timeline should not be called")

    def fetch_context_objects(_opts, _room_id),
      do: flunk("fetch_context_objects should not be called")

    def submit_contribution(_opts, room_id, _payload),
      do: {:ok, %{"data" => %{"room_id" => room_id}}}
  end

  test "refresh uses the consolidated room sync fetch and surfaces server operations" do
    {:ok, server} = SyncOnlyRoomApiStub.start_link()

    {:ok, embedded} =
      Embedded.start_link(
        room_id: "room-1",
        participant_id: "alice",
        participant_role: "operator",
        room_api: {SyncOnlyRoomApiStub, [server: server, test_pid: self()]},
        poll_interval_ms: 5_000
      )

    assert {:ok, snapshot} = Embedded.refresh(embedded)
    assert_receive {:fetch_sync, "room-1", [after: nil], _call_number}

    assert snapshot["timeline"] == [
             %{
               "body" => "Hello sync",
               "cursor" => "evt-1",
               "event_id" => "evt-1",
               "kind" => "contribution.recorded"
             }
           ]

    assert Enum.any?(snapshot["operations"], fn operation ->
             operation["operation_id"] == "room_run-1" and operation["status"] == "running"
           end)
  end
end
