Code.require_file("../build_support/dependency_resolver.exs", __DIR__)

defmodule JidoHiveClient.MixProject do
  use Mix.Project

  alias JidoHive.Build.DependencyResolver

  def project do
    [
      app: :jido_hive_client,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      escript: [
        app: nil,
        include_priv_for: [:tzdata],
        main_module: JidoHiveClient.CLI
      ],
      aliases: aliases(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:ex_unit]]
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

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {JidoHiveClient.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test_support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:phoenix_client, "~> 0.11.1"},
      {:plug_cowboy, "~> 2.7"},
      DependencyResolver.jido(override: true),
      DependencyResolver.jido_action(override: true),
      DependencyResolver.jido_signal(override: true),
      DependencyResolver.jido_harness(override: true),
      DependencyResolver.jido_shell(override: true),
      DependencyResolver.jido_vfs(override: true),
      DependencyResolver.sprites(override: true),
      DependencyResolver.external_runtime_transport(override: true),
      DependencyResolver.jido_integration_runtime_asm_bridge(override: true),
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
end
