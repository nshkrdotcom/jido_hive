defmodule JidoHiveConsole.SwitchyardBridgeTest do
  use ExUnit.Case, async: true

  alias JidoHiveConsole.SwitchyardBridge

  test "switchyard_args forwards room workflow options" do
    args =
      SwitchyardBridge.switchyard_args(
        api_base_url: "https://example.com/api",
        room_id: "room-1",
        participant_id: "alice",
        participant_role: "coordinator",
        authority_level: "binding",
        log_level: "debug"
      )

    assert args == [
             "--api-base-url",
             "https://example.com/api",
             "--room-id",
             "room-1",
             "--subject",
             "alice",
             "--participant-id",
             "alice",
             "--participant-role",
             "coordinator",
             "--authority-level",
             "binding",
             "--debug"
           ]
  end

  test "command_spec prefers an explicit switchyard binary" do
    assert {:ok,
            %{
              cmd: "/tmp/switchyard",
              args: ["--api-base-url", "https://example.com/api"],
              cd: nil
            }} =
             SwitchyardBridge.command_spec(
               api_base_url: "https://example.com/api",
               switchyard_bin: "/tmp/switchyard"
             )
  end

  test "command_spec falls back to the switchyard mix project" do
    app_dir = Path.join(System.tmp_dir!(), "switchyard_tui_#{System.unique_integer([:positive])}")
    File.mkdir_p!(app_dir)

    assert {:ok, %{cmd: "mix", cd: ^app_dir, args: args}} =
             SwitchyardBridge.command_spec(
               api_base_url: "https://example.com/api",
               switchyard_app_dir: app_dir
             )

    assert Enum.take(args, 4) == ["run", "-e", "Switchyard.TUI.CLI.main(System.argv())", "--"]
    assert Enum.take(args, -2) == ["--api-base-url", "https://example.com/api"]
  end
end
