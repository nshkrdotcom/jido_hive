defmodule JidoHiveWebWeb.PageController do
  use JidoHiveWebWeb, :controller

  def home(conn, _params), do: redirect(conn, to: ~p"/rooms")
end
