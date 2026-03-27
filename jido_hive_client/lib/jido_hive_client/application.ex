defmodule JidoHiveClient.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Application.put_env(
      :jido_harness,
      :runtime_drivers,
      Map.put(
        Application.get_env(:jido_harness, :runtime_drivers, %{}),
        :asm,
        Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver
      )
    )

    children = [
      {Jido.Signal.Bus, name: JidoHiveClient.SignalBus}
    ]

    opts = [strategy: :one_for_one, name: JidoHiveClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
