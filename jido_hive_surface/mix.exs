unless Code.ensure_loaded?(JidoHive.Build.DependencyResolver) do
  Code.require_file("../build_support/dependency_resolver.exs", __DIR__)
end

unless Code.ensure_loaded?(JidoHive.Build.PackageDocs) do
  Code.require_file("../build_support/package_docs.exs", __DIR__)
end

defmodule JidoHive.Surface.MixProject do
  use Mix.Project

  alias JidoHive.Build.PackageDocs

  def project do
    [
      app: :jido_hive_surface,
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
      {:jido_hive_client, path: "../jido_hive_client"},
      {:jido_hive_context_graph, path: "../jido_hive_context_graph"},
      {:app_kit_core, path: "../../app_kit/core/app_kit_core"},
      {:app_kit_scope_objects, path: "../../app_kit/core/scope_objects"},
      {:app_kit_chat_surface, path: "../../app_kit/core/chat_surface"},
      {:app_kit_operator_surface, path: "../../app_kit/core/operator_surface"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    PackageDocs.docs(package_title: "Jido Hive Surface")
  end
end
