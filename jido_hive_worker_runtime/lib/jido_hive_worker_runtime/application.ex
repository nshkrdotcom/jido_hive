defmodule JidoHiveWorkerRuntime.Application do
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

    runtime_opts =
      Application.get_env(:jido_hive_worker_runtime, :runtime, [])
      |> Keyword.put_new(:name, JidoHiveWorkerRuntime.Runtime)

    children =
      [
        {Jido.Signal.Bus, name: JidoHiveWorkerRuntime.SignalBus},
        {JidoHiveWorkerRuntime.Runtime, runtime_opts}
      ] ++ control_children()

    opts = [strategy: :one_for_one, name: JidoHiveWorkerRuntime.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp control_children do
    case Application.get_env(:jido_hive_worker_runtime, :control_api, []) do
      control_opts when is_list(control_opts) ->
        if Keyword.get(control_opts, :enabled, false) do
          [{JidoHiveWorkerRuntime.Control.Server, control_opts}]
        else
          []
        end

      _other ->
        []
    end
  end
end
