if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

unless Code.ensure_loaded?(JidoHive.Build.PackageDocs) do
  Code.require_file("../build_support/package_docs.exs", __DIR__)
end

defmodule JidoHive.Publications.MixProject do
  use Mix.Project

  alias JidoHive.Build.PackageDocs

  def project do
    [
      app: :jido_hive_publications,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:ex_unit, :mix, :jido_hive_server]],
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jido_hive_client, path: "../jido_hive_client"},
      {:jido_hive_context_graph, path: "../jido_hive_context_graph"},
      {:jido_hive_server, path: "../jido_hive_server", runtime: false},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.20"},
      {:jido, "~> 2.2", override: true},
      {:jido_action, "~> 2.2", override: true},
      workspace_dep(
        {:jido_signal, github: "nshkrdotcom/jido_signal", branch: "main", override: true}
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
        {:jido_integration_v2,
         github: "agentjido/jido_integration",
         branch: "main",
         subdir: "core/platform",
         override: true}
      ),
      {:phoenix, "~> 1.8.1"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2.7"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    PackageDocs.docs(package_title: "Jido Hive Publications")
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
