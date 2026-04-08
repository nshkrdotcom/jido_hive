defmodule JidoHiveTermuiConsole.CLITest do
  use ExUnit.Case, async: true

  alias JidoHiveTermuiConsole.CLI

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
end
