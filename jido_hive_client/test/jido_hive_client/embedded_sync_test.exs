defmodule JidoHiveClient.EmbeddedSyncTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Embedded

  defmodule SyncOnlyRoomApiStub do
    def start_link do
      Agent.start_link(fn -> %{calls: 0} end)
    end

    def fetch_room(opts, room_id) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      server = Keyword.fetch!(opts, :server)

      call_number =
        Agent.get_and_update(server, fn state ->
          next = state.calls + 1
          {next, %{state | calls: next}}
        end)

      send(test_pid, {:fetch_room, room_id, call_number})

      {:ok,
       %{
         "id" => room_id,
         "name" => "Sync room",
         "status" => "running",
         "participants" => [],
         "context_objects" => [
           %{
             "context_id" => "ctx-1",
             "object_type" => "message",
             "body" => "Hello sync"
           }
         ],
         "operations" => [
           %{
             "operation_id" => "room_run-1",
             "client_operation_id" => "room_run-client-1",
             "kind" => "room_run",
             "status" => "running"
           }
         ]
       }}
    end

    def list_events(opts, room_id, query_opts) do
      send(Keyword.fetch!(opts, :test_pid), {:list_events, room_id, query_opts})

      {:ok,
       %{
         entries: [
           %{
             "event_id" => "evt-1",
             "cursor" => "evt-1",
             "kind" => "contribution.submitted",
             "body" => "Hello sync"
           }
         ],
         next_cursor: "evt-1"
       }}
    end

    def submit_contribution(_opts, room_id, _payload),
      do: {:ok, %{"data" => %{"room_id" => room_id}}}
  end

  test "refresh uses explicit room detail and event listing and surfaces server operations" do
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
    assert_receive {:fetch_room, "room-1", _call_number}
    assert_receive {:list_events, "room-1", [after: nil]}

    assert snapshot["timeline"] == [
             %{
               "body" => "Hello sync",
               "cursor" => "evt-1",
               "event_id" => "evt-1",
               "kind" => "contribution.submitted"
             }
           ]

    assert Enum.any?(snapshot["operations"], fn operation ->
             operation["operation_id"] == "room_run-1" and operation["status"] == "running"
           end)
  end
end
