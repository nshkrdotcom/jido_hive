defmodule JidoHiveServer.IntegrationsBootstrap do
  @moduledoc false

  use GenServer

  alias JidoHiveServer.BoundaryRuntime
  alias Jido.Integration.V2
  alias Jido.Integration.V2.Connectors.CodexCli
  alias Jido.Integration.V2.Connectors.{GitHub, Notion}
  alias Jido.Integration.V2.ControlPlane.Stores
  alias Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver
  alias Jido.Integration.V2.TargetDescriptor

  @connectors [CodexCli, GitHub, Notion]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ok = bootstrap!()
    {:ok, %{}}
  end

  def bootstrap! do
    Application.put_env(
      :jido_harness,
      :runtime_drivers,
      Map.put(Application.get_env(:jido_harness, :runtime_drivers, %{}), :asm, HarnessDriver)
    )

    Enum.each(@connectors, fn connector ->
      :ok = register_connector(connector)
    end)

    sync_target_projection!([])
  end

  def sync_target_projection!(session_targets) when is_list(session_targets) do
    Enum.each(@connectors, &register_connector/1)
    reset_target_store!()

    server_target_descriptors()
    |> Kernel.++(session_target_descriptors(session_targets))
    |> Enum.each(fn descriptor ->
      :ok = V2.announce_target(descriptor)
    end)

    :ok
  end

  defp register_connector(module) do
    _ = V2.register_connector(module)
    :ok
  end

  defp reset_target_store! do
    target_store = Stores.target_store()

    if function_exported?(target_store, :reset!, 0) do
      :ok = target_store.reset!()
    end

    :ok
  end

  defp server_target_descriptors do
    Enum.flat_map(@connectors, &server_target_descriptors/1)
  end

  defp server_target_descriptors(module) do
    manifest = module.manifest()

    manifest.capabilities
    |> Enum.filter(&(&1.runtime_class == :direct))
    |> Enum.map(fn capability ->
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
    end)
  end

  defp workspace_root do
    Path.expand("../..", __DIR__)
  end

  defp session_target_descriptors(session_targets) do
    Enum.map(session_targets, &session_target_descriptor/1)
  end

  defp session_target_descriptor(target) do
    extensions =
      %{
        "runtime" => %{
          "driver" => target.runtime_driver,
          "provider" => target.provider
        }
      }
      |> maybe_put_boundary_extension(target)

    TargetDescriptor.new!(%{
      target_id: target.target_id,
      capability_id: target.capability_id,
      runtime_class: :session,
      version: "1.0.0",
      features: %{
        feature_ids: ["asm", target.capability_id],
        runspec_versions: ["1.0.0"],
        event_schema_versions: ["1.0.0"]
      },
      constraints: %{workspace_root: target.workspace_root},
      health: :healthy,
      location: %{
        mode: :beam,
        region: "local",
        workspace_root: target.workspace_root
      },
      extensions: extensions
    })
  end

  defp maybe_put_boundary_extension(extensions, target) do
    case BoundaryRuntime.boundary_capability(target) do
      nil -> extensions
      capability -> Map.put(extensions, "boundary", capability)
    end
  end
end
