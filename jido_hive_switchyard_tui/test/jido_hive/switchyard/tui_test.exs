defmodule JidoHive.Switchyard.TUITest do
  use ExUnit.Case, async: true

  alias JidoHive.Switchyard.Site
  alias JidoHive.Switchyard.TUI
  alias JidoHive.Switchyard.TUI.RoomsMount

  defmodule BootstrapStub do
    def start_tui_dependencies do
      send(self(), :tui_bootstrap_started)
      :ok
    end
  end

  defmodule SwitchyardTUIStub do
    def run(opts) do
      send(self(), {:switchyard_tui_run, opts})
      :ok
    end
  end

  test "bootstraps switchyard tui dependencies before delegating to the host" do
    assert :ok =
             TUI.run(
               api_base_url: "http://127.0.0.1:4000/api",
               participant_id: "alice",
               bootstrap_module: BootstrapStub,
               switchyard_tui_module: SwitchyardTUIStub
             )

    assert_received :tui_bootstrap_started

    assert_received {:switchyard_tui_run, opts}
    assert opts[:api_base_url] == "http://127.0.0.1:4000/api"
    assert opts[:participant_id] == "alice"
    assert opts[:site_modules] == [Switchyard.Site.Local, Site]
    assert opts[:mount_modules] == [RoomsMount]
    assert opts[:open_app] == RoomsMount.id()
    refute Keyword.has_key?(opts, :bootstrap_module)
    refute Keyword.has_key?(opts, :switchyard_tui_module)
  end
end
