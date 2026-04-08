defmodule JidoHiveTermuiConsole.EventLogPollerTest do
  use ExUnit.Case, async: false

  alias JidoHiveTermuiConsole.EventLogPoller
  alias JidoHiveTermuiConsole.TestHTTPServer

  test "poller maintains cursor and deduplicates repeated entries" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, server} =
      TestHTTPServer.start_link(fn request ->
        call = Agent.get_and_update(counter, fn value -> {value, value + 1} end)

        response =
          case {call, request.path} do
            {0, "/rooms/room-1/timeline"} ->
              %{
                "data" => [%{"cursor" => "c1", "kind" => "contribution.recorded"}],
                "next_cursor" => "c1"
              }

            {1, "/rooms/room-1/timeline?after=c1"} ->
              %{
                "data" => [
                  %{"cursor" => "c1", "kind" => "contribution.recorded"},
                  %{"cursor" => "c2", "kind" => "assignment.started"}
                ],
                "next_cursor" => "c2"
              }

            _other ->
              %{"data" => [], "next_cursor" => "c2"}
          end

        {200, %{}, Jason.encode!(response)}
      end)

    on_exit(fn ->
      TestHTTPServer.stop(server)
      if Process.alive?(counter), do: Agent.stop(counter)
    end)

    {:ok, pid} =
      EventLogPoller.start_link(
        room_id: "room-1",
        app_pid: self(),
        api_base_url: TestHTTPServer.base_url(server),
        poll_interval_ms: 10
      )

    assert_receive {:event_log_update, [%{"cursor" => "c1"}], "c1"}, 500
    assert_receive {:event_log_update, [%{"cursor" => "c2"}], "c2"}, 500
    Process.exit(pid, :shutdown)
  end

  test "poller tolerates failures and eventually reconnects" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, server} =
      TestHTTPServer.start_link(fn _request ->
        call = Agent.get_and_update(counter, fn value -> {value, value + 1} end)

        case call do
          0 ->
            {500, %{}, ~s({"error":"boom"})}

          1 ->
            {500, %{}, ~s({"error":"boom"})}

          _other ->
            {200, %{},
             Jason.encode!(%{
               "data" => [%{"cursor" => "c3", "kind" => "reconnected"}],
               "next_cursor" => "c3"
             })}
        end
      end)

    on_exit(fn ->
      TestHTTPServer.stop(server)
      if Process.alive?(counter), do: Agent.stop(counter)
    end)

    {:ok, pid} =
      EventLogPoller.start_link(
        room_id: "room-1",
        app_pid: self(),
        api_base_url: TestHTTPServer.base_url(server),
        poll_interval_ms: 10
      )

    assert_receive {:event_log_update, [%{"cursor" => "c3"}], "c3"}, 1_000
    Process.exit(pid, :shutdown)
  end
end
