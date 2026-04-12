unless Code.ensure_loaded?(JidoHive.Build.DependencyResolver) do
  Code.require_file("../build_support/dependency_resolver.exs", __DIR__)
end

unless Code.ensure_loaded?(JidoHive.Build.PackageDocs) do
  Code.require_file("../build_support/package_docs.exs", __DIR__)
end

defmodule JidoHive.Switchyard.TUI.MixProject do
  use Mix.Project

  alias JidoHive.Build.{DependencyResolver, PackageDocs}

  def project do
    [
      app: :jido_hive_switchyard_tui,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:ex_unit]],
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

  defp deps do
    [
      {:jido_hive_surface, path: "../jido_hive_surface"},
      {:jido_hive_switchyard_site, path: "../jido_hive_switchyard_site"},
      DependencyResolver.switchyard_tui(),
      DependencyResolver.switchyard_tui_framework(),
      DependencyResolver.switchyard_widgets(),
      DependencyResolver.switchyard_site_local(),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    PackageDocs.docs(package_title: "Jido Hive Switchyard TUI")
  end
end
