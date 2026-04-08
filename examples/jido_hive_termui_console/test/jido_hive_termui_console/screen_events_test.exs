defmodule JidoHiveTermuiConsole.ScreenEventsTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event.Key
  alias JidoHiveTermuiConsole.Model
  alias JidoHiveTermuiConsole.Screens.{Conflict, Publish, Wizard}

  test "auth device flow uses atom keys expected by the CLI" do
    assert {:ok, %{channel: "github", user_code: code, verification_uri: uri}} =
             JidoHiveTermuiConsole.Auth.start_device_flow("github")

    assert is_binary(code)
    assert uri == "https://auth.github.example/device"
  end

  test "conflict screen maps ctrl+q to quit" do
    assert Conflict.event_to_msg(
             %Key{code: "q", kind: "press", modifiers: ["ctrl"]},
             Model.new([])
           ) ==
             :quit
  end

  test "publish screen maps ctrl+q to quit" do
    assert Publish.event_to_msg(
             %Key{code: "q", kind: "press", modifiers: ["ctrl"]},
             Model.new([])
           ) ==
             :quit
  end

  test "wizard screen maps ctrl+q to quit" do
    assert Wizard.event_to_msg(%Key{code: "q", kind: "press", modifiers: ["ctrl"]}, Model.new([])) ==
             :quit
  end
end
