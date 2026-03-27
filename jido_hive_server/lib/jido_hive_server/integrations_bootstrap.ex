defmodule JidoHiveServer.IntegrationsBootstrap do
  @moduledoc false

  use GenServer

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Connectors.CodexCli
  alias Jido.Integration.V2.Connectors.{GitHub, Notion}
  alias Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver
  alias Jido.Integration.V2.TargetDescriptor

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

    Enum.each([CodexCli, GitHub, Notion], fn connector ->
      :ok = register_connector(connector)
      :ok = announce_server_targets(connector)
    end)

    {:ok, %{}}
  end

  defp register_connector(module) do
    _ = V2.register_connector(module)
    :ok
  end

  defp announce_server_targets(module) do
    manifest = module.manifest()

    manifest.capabilities
    |> Enum.filter(&(&1.runtime_class == :direct))
    |> Enum.each(fn capability ->
      descriptor =
        TargetDescriptor.new!(%{
          target_id: "target-server-#{String.replace(capability.id, ".", "-")}",
          capability_id: capability.id,
          runtime_class: :direct,
          version: "1.0.0",
          features: %{
            feature_ids: [capability.id],
            runspec_versions: ["1.0.0"],
            event_schema_versions: ["1.0.0"]
          },
          constraints: %{workspace_root: workspace_root()},
          health: :healthy,
          location: %{mode: :beam, region: "local", workspace_root: workspace_root()},
          extensions: %{
            "runtime" => %{
              "driver" => "direct",
              "provider" => manifest.connector,
              "execution_host" => "jido_hive_server"
            }
          }
        })

      _ = V2.announce_target(descriptor)
    end)

    :ok
  end

  defp workspace_root do
    Path.expand("../..", __DIR__)
  end
end
