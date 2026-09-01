if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

unless Code.ensure_loaded?(JidoHive.Build.PackageDocs) do
  Code.require_file("../build_support/package_docs.exs", __DIR__)
end

defmodule JidoHiveWorkerRuntime.MixProject do
  use Mix.Project

  alias JidoHive.Build.PackageDocs

  def project do
    [
      app: :jido_hive_worker_runtime,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      escript: [
        app: nil,
        include_priv_for: [:erlexec, :tzdata],
        main_module: JidoHiveWorkerRuntime.CLI,
        name: "jido_hive_worker"
      ],
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:ex_unit]],
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {JidoHiveWorkerRuntime.Application, []}
    ]
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

  defp elixirc_paths(:test), do: ["lib", "test_support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:phoenix_client, "~> 0.11.1"},
      {:plug_cowboy, "~> 2.7"},
      {:jido, "~> 2.2", override: true},
      workspace_dep(
        {:jido_signal, github: "nshkrdotcom/jido_signal", branch: "main", override: true}
      ),
      workspace_dep(
        {:jido_harness, github: "nshkrdotcom/jido_harness", branch: "main", override: true}
      ),
      workspace_dep(
        {:jido_shell, github: "nshkrdotcom/jido_shell", branch: "main", override: true}
      ),
      workspace_dep({:jido_vfs, github: "nshkrdotcom/jido_vfs", branch: "main", override: true}),
      workspace_dep(
        {:sprites, github: "mikehostetler/sprites-ex", branch: "main", override: true}
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
        {:jido_integration_v2_asm_runtime_bridge,
         github: "agentjido/jido_integration",
         branch: "main",
         subdir: "core/asm_runtime_bridge",
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
    PackageDocs.docs(package_title: "Jido Hive Worker Runtime")
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
