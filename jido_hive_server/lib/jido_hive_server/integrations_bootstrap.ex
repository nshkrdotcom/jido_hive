defmodule JidoHiveServer.IntegrationsBootstrap do
  @moduledoc false

  use GenServer

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Connectors.CodexCli
  alias Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Application.put_env(
      :jido_harness,
      :runtime_drivers,
      Map.put(Application.get_env(:jido_harness, :runtime_drivers, %{}), :asm, HarnessDriver)
    )

    _ = register_connector(CodexCli)
    {:ok, %{}}
  end

  defp register_connector(module) do
    case V2.register_connector(module) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end
end
