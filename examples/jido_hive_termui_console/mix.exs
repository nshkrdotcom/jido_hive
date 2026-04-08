defmodule JidoHiveTermuiConsole.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_hive_termui_console,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      escript: [main_module: JidoHiveTermuiConsole.CLI, name: "hive"],
      aliases: aliases(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:ex_unit]],
      docs: [main: "readme", extras: ["README.md"]]
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
        docs: :dev,
        quality: :test
      ]
    ]
  end

  defp deps do
    [
      term_ui_dependency(),
      {:jason, "~> 1.4"},
      {:jido_hive_client, path: "../../jido_hive_client"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false}
    ]
  end

  defp term_ui_dependency do
    local_path = Path.expand("../../../term_ui", __DIR__)

    if File.dir?(local_path) do
      {:term_ui, path: local_path}
    else
      {:term_ui, "~> 0.2.0"}
    end
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
