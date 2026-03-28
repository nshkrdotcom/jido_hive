defmodule JidoHiveClient.StatusTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias JidoHiveClient.Status

  test "client_start prints the selected websocket endpoint" do
    output =
      capture_io(fn ->
        Status.client_start(
          participant_id: "skeptic",
          participant_role: "skeptic",
          target_id: "target-skeptic",
          executor: {JidoHiveClient.Executor.Session, [provider: :codex]},
          relay_topic: "relay:workspace-prod",
          workspace_id: "workspace-prod",
          url: "wss://jido-hive-server-test.app.nsai.online/socket/websocket"
        )
      end)

    assert output =~ "participant=skeptic"
    assert output =~ "relay=relay:workspace-prod"
    assert output =~ "workspace=workspace-prod"
    assert output =~ "url=wss://jido-hive-server-test.app.nsai.online/socket/websocket"
  end

  test "relay_ready says the client is waiting for relay work" do
    output =
      capture_io(fn ->
        Status.relay_ready(%{
          participant_id: "architect",
          participant_role: "architect",
          target_id: "target-architect",
          capability_id: "codex.exec.session",
          relay_topic: "relay:workspace-prod",
          workspace_id: "workspace-prod",
          socket_url: "wss://jido-hive-server-test.app.nsai.online/socket/websocket",
          executor: {JidoHiveClient.Executor.Session, [provider: :codex]}
        })
      end)

    assert output =~ "ready participant=architect"
    assert output =~ "relay=relay:workspace-prod"
    assert output =~ "waiting_for=job.start"
    assert output =~ "url=wss://jido-hive-server-test.app.nsai.online/socket/websocket"
  end
end
