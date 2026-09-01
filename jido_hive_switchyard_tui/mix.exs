if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

unless Code.ensure_loaded?(JidoHive.Build.PackageDocs) do
  Code.require_file("../build_support/package_docs.exs", __DIR__)
end

defmodule JidoHive.Switchyard.TUI.MixProject do
  use Mix.Project

  alias JidoHive.Build.PackageDocs

  def project do
    [
      app: :jido_hive_switchyard_tui,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:ex_unit]],
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [
      preferred_envs: [
        credo: :test,
        dialyzer: :test,
        docs: :dev
      ]
    ]
  end

  defp deps do
    [
      {:jido_hive_publications, path: "../jido_hive_publications"},
      {:jido_hive_surface, path: "../jido_hive_surface"},
      {:jido_hive_switchyard_site, path: "../jido_hive_switchyard_site"},
      workspace_dep(
        {:jido_signal, github: "nshkrdotcom/jido_signal", branch: "main", override: true}
      ),
      workspace_dep(
        {:jido_integration_contracts,
         github: "agentjido/jido_integration",
         branch: "main",
         subdir: "core/contracts",
         override: true}
      ),
      workspace_dep(
        {:jido_integration_v2,
         github: "agentjido/jido_integration",
         branch: "main",
         subdir: "core/platform",
         override: true}
      ),
      workspace_dep(
        {:execution_plane,
         github: "nshkrdotcom/execution_plane",
         branch: "main",
         subdir: "core/execution_plane",
         override: true}
      ),
      workspace_dep(
        {:ground_plane_contracts,
         github: "nshkrdotcom/ground_plane",
         branch: "main",
         subdir: "core/ground_plane_contracts",
         override: true}
      ),
      workspace_dep(
        {:ground_plane_persistence_policy,
         github: "nshkrdotcom/ground_plane",
         branch: "main",
         subdir: "core/persistence_policy",
         override: true}
      ),
      workspace_dep(
        {:switchyard_tui,
         github: "nshkrdotcom/switchyard", branch: "main", subdir: "apps/terminal_workbench_tui"}
      ),
      workspace_dep(
        {:workbench_tui_framework,
         github: "nshkrdotcom/switchyard", branch: "main", subdir: "core/workbench_tui_framework"}
      ),
      workspace_dep(
        {:workbench_widgets,
         github: "nshkrdotcom/switchyard", branch: "main", subdir: "core/workbench_widgets"}
      ),
      workspace_dep(
        {:switchyard_site_local,
         github: "nshkrdotcom/switchyard", branch: "main", subdir: "sites/site_local"}
      ),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    PackageDocs.docs(package_title: "Jido Hive Switchyard TUI")
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
