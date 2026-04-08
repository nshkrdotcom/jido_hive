defmodule JidoHiveTermuiConsole.HTTPTest do
  use ExUnit.Case, async: false

  alias JidoHiveTermuiConsole.HTTP
  alias JidoHiveTermuiConsole.TestHTTPServer

  test "get returns decoded map on 200" do
    {:ok, server} =
      TestHTTPServer.start_link(fn _request ->
        {200, %{}, ~s({"data":{"room_id":"room-1"}})}
      end)

    on_exit(fn -> TestHTTPServer.stop(server) end)

    assert HTTP.get(TestHTTPServer.base_url(server), "/rooms/room-1") ==
             {:ok, %{"data" => %{"room_id" => "room-1"}}}
  end

  test "get returns not_found on 404" do
    {:ok, server} =
      TestHTTPServer.start_link(fn _request ->
        {404, %{}, ~s({"error":"room_not_found"})}
      end)

    on_exit(fn -> TestHTTPServer.stop(server) end)

    assert HTTP.get(TestHTTPServer.base_url(server), "/rooms/missing") == {:error, :not_found}
  end

  test "post returns decoded map on 201" do
    test_pid = self()

    {:ok, server} =
      TestHTTPServer.start_link(fn request ->
        send(test_pid, {:request_body, request.body})
        {201, %{}, ~s({"data":{"ok":true}})}
      end)

    on_exit(fn -> TestHTTPServer.stop(server) end)

    assert HTTP.post(TestHTTPServer.base_url(server), "/rooms", %{"brief" => "Create room"}) ==
             {:ok, %{"data" => %{"ok" => true}}}

    assert_receive {:request_body, body}
    assert Jason.decode!(body) == %{"brief" => "Create room"}
  end
end
