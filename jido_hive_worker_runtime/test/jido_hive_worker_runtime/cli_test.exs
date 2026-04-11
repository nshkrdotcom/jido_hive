defmodule JidoHiveWorkerRuntime.CLITest do
  use ExUnit.Case, async: true

  alias JidoHiveWorkerRuntime.CLI

  test "run returns help for help flags" do
    assert {:help, output} = CLI.run(["--help"])
    assert output =~ "jido_hive_worker [options]"
    assert output =~ "--participant-id"
    assert output =~ "--control-port"
  end

  test "run normalizes valid worker runtime options" do
    assert {:ok, opts} =
             CLI.run([
               "--url",
               "ws://127.0.0.1:4000/socket/websocket",
               "--participant-id",
               "worker-01",
               "--participant-role",
               "worker",
               "--target-id",
               "target-worker-01",
               "--user-id",
               "user-worker-01"
             ])

    assert Keyword.fetch!(opts, :url) == "ws://127.0.0.1:4000/socket/websocket"
    assert Keyword.fetch!(opts, :participant_id) == "worker-01"
    assert Keyword.fetch!(opts, :participant_role) == "worker"
    assert Keyword.fetch!(opts, :target_id) == "target-worker-01"
    assert Keyword.fetch!(opts, :user_id) == "user-worker-01"
  end

  test "run returns invalid option errors without raising" do
    assert CLI.run(["--help-me"]) == {:error, {:invalid_options, [{"--help-me", nil}]}}
  end
end
