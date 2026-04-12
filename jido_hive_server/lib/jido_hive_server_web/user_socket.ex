defmodule JidoHiveServerWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", JidoHiveServerWeb.RoomChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok,
     socket
     |> assign(:session_seed, System.unique_integer([:positive, :monotonic]))}
  end

  @impl true
  def id(_socket), do: nil
end
