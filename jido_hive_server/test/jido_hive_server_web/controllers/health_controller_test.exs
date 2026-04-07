defmodule JidoHiveServerWeb.HealthControllerTest do
  use JidoHiveServerWeb.ConnCase, async: true

  test "returns a minimal health response", %{conn: conn} do
    conn = get(conn, "/healthz")

    assert response(conn, 200) == "ok"
    assert ["text/plain; charset=utf-8"] = get_resp_header(conn, "content-type")
    assert ["no-store"] = get_resp_header(conn, "cache-control")
  end
end
