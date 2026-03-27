Code.require_file("../build_support/dependency_resolver.exs", __DIR__)

defmodule JidoHiveClient.MixProject do
  use Mix.Project

  alias JidoHive.Build.DependencyResolver

  def project do
    [
      app: :jido_hive_client,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: JidoHiveClient.CLI],
      aliases: aliases(),
      deps: deps()
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
      DependencyResolver.jido_integration_runtime_asm_bridge()
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
