if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

unless Code.ensure_loaded?(JidoHive.Build.PackageDocs) do
  Code.require_file("../../build_support/package_docs.exs", __DIR__)
end

defmodule JidoHiveConsole.MixProject do
  use Mix.Project

  alias JidoHive.Build.PackageDocs

  def project do
    [
      app: :jido_hive_console,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      escript: [
        app: nil,
        include_priv_for: [:tzdata],
        main_module: JidoHiveConsole.CLI,
        name: "hive"
      ],
      aliases: aliases(),
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
        docs: :dev,
        quality: :test
      ]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:jido_hive_client, path: "../../jido_hive_client"},
      {:jido_hive_switchyard_tui, path: "../../jido_hive_switchyard_tui"},
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      quality: [
        "format --check-formatted",
        "compile",
        "test",
        "credo --strict",
        "dialyzer",
        "cmd env MIX_ENV=dev mix docs --warnings-as-errors"
      ]
    ]
  end

  defp docs do
    PackageDocs.docs(package_title: "Jido Hive Console", root_prefix: "../..")
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
