unless Code.ensure_loaded?(JidoHive.Build.DependencyResolver) do
  Code.require_file("../build_support/dependency_resolver.exs", __DIR__)
end

unless Code.ensure_loaded?(JidoHive.Build.PackageDocs) do
  Code.require_file("../build_support/package_docs.exs", __DIR__)
end

defmodule JidoHive.Publications.MixProject do
  use Mix.Project

  alias JidoHive.Build.{DependencyResolver, PackageDocs}

  def project do
    [
      app: :jido_hive_publications,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:ex_unit, :mix, :jido_hive_server]],
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
        docs: :dev
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jido_hive_client, path: "../jido_hive_client"},
      {:jido_hive_context_graph, path: "../jido_hive_context_graph"},
      {:jido_hive_server, path: "../jido_hive_server", runtime: false},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.20"},
      DependencyResolver.jido(override: true),
      DependencyResolver.jido_action(override: true),
      DependencyResolver.jido_signal(override: true),
      DependencyResolver.jido_integration_platform(),
      {:phoenix, "~> 1.8.1"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    PackageDocs.docs(package_title: "Jido Hive Publications")
  end
end
