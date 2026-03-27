defmodule JidoHiveClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_hive_client,
      version: "0.1.0",
      elixir: "~> 1.18",
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
      {:jido, path: "../../jido", override: true},
      {:jido_action, path: "../../jido_action", override: true},
      {:jido_signal, path: "../../jido_signal", override: true},
      {:jido_harness, path: "../../jido_harness", override: true},
      {:jido_integration_v2_runtime_asm_bridge,
       path: "../../jido_integration/core/runtime_asm_bridge"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
