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
      blitz_dependency()
    ]
  end

  defp blitz_dependency do
    local_path = Path.expand("../blitz", __DIR__)

    if File.dir?(local_path) do
      {:blitz, path: local_path, runtime: false}
    else
      {:blitz, "~> 0.1.0", runtime: false}
    end
  end

  defp aliases do
    monorepo_aliases = [
      "monorepo.deps.get": ["blitz.workspace deps_get"],
      "monorepo.format": ["blitz.workspace format"],
      "monorepo.compile": ["blitz.workspace compile"],
      "monorepo.test": ["blitz.workspace test"],
      "monorepo.credo": ["blitz.workspace credo"],
      "monorepo.dialyzer": ["blitz.workspace dialyzer"],
      "monorepo.docs": ["blitz.workspace docs"]
    ]

    mr_aliases =
      ~w[deps.get format compile test credo dialyzer docs]
      |> Enum.map(fn task -> {:"mr.#{task}", ["monorepo.#{task}"]} end)

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
      "docs.all": ["monorepo.docs"]
    ] ++ monorepo_aliases ++ mr_aliases
  end

  defp blitz_workspace do
    [
      root: __DIR__,
      projects: [
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
        env: "JIDO_HIVE_MONOREPO_MAX_CONCURRENCY",
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
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
