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
end
