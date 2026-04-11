defmodule JidoHiveConsoleTest do
  use ExUnit.Case, async: true

  defmodule BootstrapStub do
    def start_cli_dependencies do
      send(self(), :bootstrap_started)
      :ok
    end
  end

  defmodule TUIStub do
    def run(opts) do
      send(self(), {:run, opts})
      :ok
    end
  end

  test "delegates console startup to the configured tui module" do
    assert :ok =
             JidoHiveConsole.run(
               api_base_url: "http://127.0.0.1:4000/api",
               bootstrap_module: BootstrapStub,
               tui_module: TUIStub
             )

    assert_received :bootstrap_started

    assert_received {:run,
                     [
                       api_base_url: "http://127.0.0.1:4000/api",
                       bootstrap_module: BootstrapStub,
                       tui_module: TUIStub
                     ]}
  end
end
