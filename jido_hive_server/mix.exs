Code.require_file("../build_support/dependency_resolver.exs", __DIR__)

defmodule JidoHiveServer.MixProject do
  use Mix.Project

  alias JidoHive.Build.DependencyResolver

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
      dialyzer: [plt_add_apps: [:ex_unit]]
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
      DependencyResolver.jido(override: true),
      DependencyResolver.jido_action(override: true),
      DependencyResolver.jido_signal(override: true),
      DependencyResolver.jido_harness(override: true),
      DependencyResolver.jido_shell(override: true),
      DependencyResolver.jido_vfs(override: true),
      DependencyResolver.sprites(override: true),
      DependencyResolver.jido_integration_platform(),
      DependencyResolver.jido_integration_runtime_asm_bridge(override: true),
      DependencyResolver.jido_integration_codex_cli(),
      DependencyResolver.jido_integration_github(),
      DependencyResolver.jido_integration_notion(),
      DependencyResolver.coolify_ex(only: :coolify, runtime: false),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false},
      {:jido_hive_client, path: "../jido_hive_client", only: :test},
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
        "../docs/architecture.md": [title: "Architecture"],
        "../setup/README.md": [title: "Setup Toolkit"],
        "../docs/developer/multi_agent_round_robin.md": [
          title: "Developer Guide: Multi-Agent Round Robin"
        ]
      ],
      groups_for_extras: [
        "Project Overview": ["../README.md"],
        "User Guides": ["../docs/architecture.md", "../setup/README.md"],
        "Developer Guides": ["../docs/developer/multi_agent_round_robin.md"]
      ],
      source_url: @source_url
    ]
  end
end
