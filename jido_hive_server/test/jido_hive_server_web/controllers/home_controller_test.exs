defmodule JidoHiveServerWeb.HomeControllerTest do
  use JidoHiveServerWeb.ConnCase, async: true

  test "renders a friendly landing page for browser requests", %{conn: conn} do
    conn = get(conn, "/")

    body = html_response(conn, 200)

    assert body =~ "Jido Hive Server"
    assert body =~ "Production browser visits land here instead of a raw JSON 404."
    assert body =~ "bin/client-worker --prod --worker-index 1"
    assert body =~ "participant_count * 3"
    assert body =~ "/api/targets"
  end

  test "renders structured metadata for json requests to the root path", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/")

    assert %{
             "name" => "Jido Hive Server",
             "status" => "ok",
             "helpers" => %{"prod" => %{"worker" => "bin/client-worker --prod --worker-index 1"}},
             "demo" => %{"strategy" => "round_robin", "max_clients" => 39},
             "endpoints" => %{"api_base" => api_base, "websocket" => websocket}
           } = json_response(conn, 200)

    assert api_base =~ "/api"
    assert websocket =~ "/socket/websocket"
  end

  test "renders a friendly html 404 for unknown browser get routes", %{conn: conn} do
    conn = get(conn, "/missing")

    body = html_response(conn, 404)

    assert body =~ "Route Not Found"
    assert body =~ "/missing"
  end

  test "preserves json 404s for unknown api routes", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/missing")

    assert json_response(conn, 404) == %{"errors" => %{"detail" => "Not Found"}}
  end
end
