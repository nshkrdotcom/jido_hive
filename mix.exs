defmodule JidoHiveWorkspace.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/jido_hive"

  def project do
    [
      app: :jido_hive_workspace,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      aliases: aliases(),
      blitz_workspace: blitz_workspace(),
      description: "Workspace tooling root for the Jido Hive repository"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:blitz, "~> 0.3.0", runtime: false}
    ]
  end

  defp aliases do
    monorepo_aliases = [
      "monorepo.deps.get": ["blitz.workspace.impact deps_get --"],
      "monorepo.format": ["blitz.workspace.impact format --"],
      "monorepo.compile": ["blitz.workspace.impact compile --"],
      "monorepo.test": ["blitz.workspace.impact test --"],
      "monorepo.credo": ["blitz.workspace.impact credo --"],
      "monorepo.dialyzer": ["blitz.workspace.impact dialyzer --"],
      "monorepo.docs": ["blitz.workspace.impact docs --"]
    ]

    [
      ci: [
        "monorepo.deps.get",
        "monorepo.format --check-formatted",
        "monorepo.compile",
        "monorepo.test",
        "monorepo.credo --strict",
        "monorepo.dialyzer",
        "monorepo.docs"
      ],
      quality: ["monorepo.credo --strict", "monorepo.dialyzer"],
      "docs.all": ["monorepo.docs"],
      "mr.deps.get": ["monorepo.deps.get"],
      "mr.format": ["monorepo.format"],
      "mr.compile": ["monorepo.compile"],
      "mr.test": ["monorepo.test"],
      "mr.credo": ["monorepo.credo"],
      "mr.dialyzer": ["monorepo.dialyzer"],
      "mr.docs": ["monorepo.docs"]
    ] ++ monorepo_aliases
  end

  defp blitz_workspace do
    [
      root: __DIR__,
      projects: [
        "core/agent_coordinator",
        "core/inter_agent_messaging",
        "core/shared_memory_facade",
        "core/coordination_patterns",
        "core/skill_contracts",
        "core/skill_engine",
        "conformance_contracts/skill_conformance_contracts",
        "jido_hive_client",
        "jido_hive_context_graph",
        "jido_hive_publications",
        "jido_hive_surface",
        "jido_hive_worker_runtime",
        "jido_hive_server",
        "jido_hive_switchyard_site",
        "jido_hive_switchyard_tui",
        "jido_hive_web",
        "examples/jido_hive_console"
      ],
      isolation: [
        deps_path: true,
        build_path: true,
        lockfile: true,
        hex_home: "_build/hex",
        unset_env: ["HEX_API_KEY", "SSLKEYLOGFILE"]
      ],
      parallelism: [
        max_concurrency: nil,
        multiplier: :auto,
        base: [
          deps_get: 3,
          format: 4,
          compile: 2,
          test: 1,
          credo: 2,
          dialyzer: 1,
          docs: 1
        ],
        overrides: []
      ],
      tasks: [
        deps_get: [args: ["deps.get"], preflight?: false],
        format: [args: ["format"]],
        test: [args: ["test"], mix_env: "test", color: true],
        compile: [args: ["compile", "--warnings-as-errors"]],
        credo: [args: ["credo"]],
        dialyzer: [args: ["dialyzer", "--force-check"]],
        docs: [args: ["docs", "--warnings-as-errors"], mix_env: "dev"]
      ]
    ]
  end

  defp package do
    [
      files: ["build_support", "mix.exs", "README.md", "LICENSE"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
