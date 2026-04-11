defmodule JidoHiveConsole.CLITest do
  use ExUnit.Case, async: true

  alias JidoHiveConsole.CLI

  test "parse_args with no args opens the lobby" do
    assert CLI.parse_args([]) == {:lobby, %{}}
    assert CLI.parse_args(["console"]) == {:lobby, %{}}
  end

  test "parse_args with room id opens a room directly" do
    assert CLI.parse_args(["--room-id", "foo"]) == {:room, %{room_id: "foo"}}
    assert CLI.parse_args(["console", "--room-id", "foo"]) == {:room, %{room_id: "foo"}}
  end

  test "parse_console_opts maps --prod to the production api base url" do
    assert CLI.parse_console_opts(["--prod"]) == [
             api_base_url: "https://jido-hive-server-test.app.nsai.online/api"
           ]
  end

  test "parse_console_opts preserves explicit api base url over mode flags" do
    assert CLI.parse_console_opts([
             "--prod",
             "--api-base-url",
             "https://example.com/api"
           ]) == [api_base_url: "https://example.com/api"]
  end

  test "parse_console_opts preserves tenant and actor ids" do
    assert CLI.parse_console_opts([
             "--tenant-id",
             "workspace-demo",
             "--actor-id",
             "operator-demo"
           ]) == [tenant_id: "workspace-demo", actor_id: "operator-demo"]
  end

  test "parse_console_opts maps --debug to debug log level" do
    assert CLI.parse_console_opts(["--debug"]) == [log_level: "debug"]
  end

  test "parse_console_opts preserves explicit log level over --debug" do
    assert CLI.parse_console_opts(["--debug", "--log-level", "error"]) == [log_level: "error"]
  end

  test "help_text documents the main console entrypoints" do
    output = CLI.help_text(:main)

    assert output =~ "hive console"
    assert output =~ "hive workflow room-smoke"
    assert output =~ "hive help"
  end

  test "help_text documents the console-specific flags" do
    output = CLI.help_text(:console)

    assert output =~ "--participant-id"
    assert output =~ "--room-id"
    assert output =~ "--debug"
  end

  test "help_text documents the workflow room smoke flags" do
    output = CLI.help_text(:workflow_room_smoke)

    assert output =~ "--brief"
    assert output =~ "--text"
    assert output =~ "--run"
  end

  test "run_status returns success for help entrypoints" do
    assert CLI.run_status(["help"]) == 0
    assert CLI.run_status(["console", "--help"]) == 0
    assert CLI.run_status(["workflow", "room-smoke", "--help"]) == 0
  end
end
