defmodule JidoHiveClient.Control.EventsControllerTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  alias JidoHiveClient.{Control.Router, Runtime}

  defp runtime_opts do
    [
      workspace_id: "workspace-1",
      user_id: "user-1",
      participant_id: "participant-1",
      participant_role: "architect",
      target_id: "target-1",
      capability_id: "capability-1",
      workspace_root: "/workspace",
      executor: {JidoHiveClient.Executor.Scripted, [provider: :codex, role: :architect]},
      runtime_id: :asm
    ]
  end

  setup do
    {:ok, runtime} = start_supervised({Runtime, runtime_opts()})
    [runtime: runtime]
  end

  test "GET /api/events returns runtime events as JSON", %{runtime: runtime} do
    :ok = Runtime.update_connection(runtime, :ready, %{})

    conn = call_router(conn(:get, "/api/events"), runtime)
    body = Jason.decode!(conn.resp_body)

    assert conn.status == 200
    assert [%{"type" => "client.connection.changed"}] = body["events"]
    assert body["next_cursor"] == "client-event-1"
  end

  test "GET /api/events filters by cursor", %{runtime: runtime} do
    :ok = Runtime.update_connection(runtime, :ready, %{})
    [first] = Runtime.recent_events(runtime)
    :ok = Runtime.update_connection(runtime, :waiting_socket, %{"reason" => "disconnect"})

    conn = call_router(conn(:get, "/api/events?after=#{first.event_id}"), runtime)
    body = Jason.decode!(conn.resp_body)

    assert conn.status == 200

    assert [
             %{
               "type" => "client.connection.changed",
               "payload" => %{"status" => "waiting_socket"}
             }
           ] =
             body["events"]
  end

  test "GET /api/events streams SSE backlog in once mode", %{runtime: runtime} do
    :ok = Runtime.update_connection(runtime, :ready, %{})

    conn =
      conn(:get, "/api/events?stream=true&once=true")
      |> put_req_header("accept", "text/event-stream")
      |> call_router(runtime)

    assert conn.status == 200
    assert List.first(get_resp_header(conn, "content-type")) =~ "text/event-stream"
    assert conn.resp_body =~ "event: client.connection.changed"
    assert conn.resp_body =~ "\"type\":\"client.connection.changed\""
  end

  defp call_router(conn, runtime, extra_opts \\ []) do
    Router.call(conn, Router.init(Keyword.merge([runtime: runtime], extra_opts)))
  end
end
