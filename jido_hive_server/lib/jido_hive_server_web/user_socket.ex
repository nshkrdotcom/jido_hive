defmodule JidoHiveServerWeb.UserSocket do
  use Phoenix.Socket

  channel "relay:*", JidoHiveServerWeb.RelayChannel

  @impl true
  def connect(params, socket, _connect_info) do
    {:ok,
     socket
     |> assign(:workspace_id, params["workspace_id"] || "workspace-local")
     |> assign(:user_id, params["user_id"] || "anonymous")}
  end

  @impl true
  def id(_socket), do: nil
end
