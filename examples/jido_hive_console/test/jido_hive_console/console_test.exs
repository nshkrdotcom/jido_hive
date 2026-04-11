defmodule JidoHiveConsoleTest do
  use ExUnit.Case, async: true

  defmodule TUIStub do
    def run(opts) do
      send(self(), {:run, opts})
      :ok
    end
  end

  test "delegates console startup to the configured tui module" do
    assert :ok =
             JidoHiveConsole.run(api_base_url: "http://127.0.0.1:4000/api", tui_module: TUIStub)

    assert_received {:run, [api_base_url: "http://127.0.0.1:4000/api", tui_module: TUIStub]}
  end
end
