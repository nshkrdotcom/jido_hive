unless Code.ensure_loaded?(JidoHive.Build.PackageDocs) do
  Code.require_file("../../build_support/package_docs.exs", __DIR__)
end

defmodule JidoHive.CoordinationPatterns.MixProject do
  use Mix.Project

  alias JidoHive.Build.PackageDocs

  def project do
    [
      app: :jido_hive_coordination_patterns,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:ex_unit]],
      docs:
        PackageDocs.docs(package_title: "Jido Hive Coordination Patterns", root_prefix: "../.."),
      name: "Jido Hive Coordination Patterns",
      description: "Bounded multi-agent coordination pattern contracts"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [ci: :test, credo: :test, dialyzer: :test, docs: :dev]]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false}
    ]
  end
end
