defmodule JidoHiveClient.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Jido.Signal.Bus, name: JidoHiveClient.SignalBus}
    ]

    opts = [strategy: :one_for_one, name: JidoHiveClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
