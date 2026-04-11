unless Code.ensure_loaded?(JidoHiveClient.Build.DependencyResolver) do
  Code.require_file("build_support/dependency_resolver.exs", __DIR__)
end

unless Code.ensure_loaded?(JidoHive.Build.PackageDocs) do
  Code.require_file("../build_support/package_docs.exs", __DIR__)
end

defmodule JidoHiveClient.MixProject do
  use Mix.Project

  alias JidoHive.Build.PackageDocs
  alias JidoHiveClient.Build.DependencyResolver

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
        include_priv_for: [:erlexec, :tzdata],
        main_module: JidoHiveClient.CLI
      ],
      aliases: aliases(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:ex_unit]],
      docs: docs()
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

  defp docs do
    PackageDocs.docs(package_title: "Jido Hive Client")
  end
end
