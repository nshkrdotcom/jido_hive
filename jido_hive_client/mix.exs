Code.require_file("../build_support/dependency_resolver.exs", __DIR__)

defmodule JidoHiveClient.MixProject do
  use Mix.Project

  alias JidoHive.Build.DependencyResolver

  def project do
    [
      app: :jido_hive_client,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      escript: [main_module: JidoHiveClient.CLI],
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

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {JidoHiveClient.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:phoenix_client, "~> 0.11.1"},
      DependencyResolver.jido(override: true),
      DependencyResolver.jido_action(override: true),
      DependencyResolver.jido_signal(override: true),
      DependencyResolver.jido_harness(override: true),
      DependencyResolver.jido_integration_runtime_asm_bridge(override: true),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false}
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
        "docs"
      ]
    ]
  end
end
