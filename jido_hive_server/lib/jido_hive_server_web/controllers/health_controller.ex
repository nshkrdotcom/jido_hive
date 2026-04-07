defmodule JidoHiveServerWeb.HealthController do
  use JidoHiveServerWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/plain")
    |> send_resp(:ok, "ok")
  end
end
