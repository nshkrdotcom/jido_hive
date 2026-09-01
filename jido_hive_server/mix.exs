if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule JidoHiveServer.MixProject do
  use Mix.Project

  @source_url "https://github.com/nshkrdotcom/jido_hive"

  def project do
    [
      app: :jido_hive_server,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      source_url: @source_url,
      docs: docs(),
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: [plt_add_apps: [:ex_unit, :mix]]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {JidoHiveServer.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [
        credo: :test,
        dialyzer: :test,
        docs: :dev,
        "coolify.app_logs": :coolify,
        "coolify.deploy": :coolify,
        "coolify.latest": :coolify,
        "coolify.logs": :coolify,
        "coolify.status": :coolify,
        precommit: :test,
        quality: :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.20"},
      {:jido_hive_context_graph, path: "../jido_hive_context_graph"},
      {:jido, "~> 2.2", override: true},
      {:jido_action, "~> 2.2", override: true},
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
        {:pristine,
         github: "nshkrdotcom/pristine",
         branch: "main",
         subdir: "apps/pristine_runtime",
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
        {:jido_integration_v2,
         github: "agentjido/jido_integration",
         branch: "main",
         subdir: "core/platform",
         override: true}
      ),
      workspace_dep(
        {:jido_integration_v2_asm_runtime_bridge,
         github: "agentjido/jido_integration",
         branch: "main",
         subdir: "core/asm_runtime_bridge",
         override: true}
      ),
      workspace_dep(
        {:jido_integration_v2_github,
         github: "agentjido/jido_integration", branch: "main", subdir: "connectors/github"}
      ),
      workspace_dep(
        {:jido_integration_v2_notion,
         github: "agentjido/jido_integration", branch: "main", subdir: "connectors/notion"}
      ),
      {:coolify_ex, "~> 0.5.1", only: :coolify, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false},
      {:jido_hive_worker_runtime, path: "../jido_hive_worker_runtime", only: :test},
      {:phoenix_client, "~> 0.11.1", only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
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
      ],
      test_all: ["test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  defp docs do
    [
      extras: [
        "../README.md": [title: "Overview"],
        "../LICENSE": [title: "License"],
        "../docs/architecture.md": [title: "Architecture"],
        "../docs/debugging_guide.md": [title: "Debugging Guide"],
        "../setup/README.md": [title: "Setup Toolkit"],
        "../docs/developer/multi_agent_round_robin.md": [
          title: "Developer Guide: Multi-Agent Round Robin"
        ]
      ],
      groups_for_extras: [
        "Project Overview": ["../README.md", "../LICENSE"],
        "User Guides": [
          "../docs/architecture.md",
          "../docs/debugging_guide.md",
          "../setup/README.md"
        ],
        "Developer Guides": ["../docs/developer/multi_agent_round_robin.md"]
      ],
      source_url: @source_url
    ]
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
