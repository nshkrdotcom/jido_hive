defmodule JidoHiveClient.StatusTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Jido.Harness.RunRequest
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

  test "execution_started prints prompt previews for the pending llm call" do
    request =
      RunRequest.new!(%{
        prompt: "Execute the current collaboration turn.\n{\"room_id\":\"room-1\"}",
        system_prompt: "Return strict JSON only.",
        allowed_tools: [],
        metadata: %{}
      })

    output =
      capture_io(fn ->
        Status.execution_started(
          %{
            "room_id" => "room-1",
            "collaboration_envelope" => %{"turn" => %{"phase" => "proposal"}}
          },
          [
            provider: :codex,
            model: "gpt-5.4",
            reasoning_effort: :low,
            executor: {JidoHiveClient.Executor.Session, [provider: :codex]},
            relay_topic: "relay:workspace-prod",
            workspace_id: "workspace-prod",
            url: "wss://jido-hive-server-test.app.nsai.online/socket/websocket",
            target_id: "target-architect",
            participant_id: "architect",
            participant_role: "architect",
            socket_url: "wss://jido-hive-server-test.app.nsai.online/socket/websocket",
            capability_id: "codex.exec.session"
          ],
          request
        )
      end)

    assert output =~
             "executing room=room-1 phase=proposal provider=codex assigned_role=architect model=gpt-5.4"

    assert output =~ "system prompt preview room=room-1 phase=proposal"
    assert output =~ "Return strict JSON only."
    assert output =~ "user prompt preview room=room-1 phase=proposal"
    assert output =~ "{\"room_id\":\"room-1\"}"
  end

  test "execution_finished prints a response preview before the summary" do
    output =
      capture_io(fn ->
        Status.execution_finished(
          %{
            "room_id" => "room-1",
            "collaboration_envelope" => %{"turn" => %{"phase" => "proposal"}}
          },
          %{
            "status" => "failed",
            "actions" => [],
            "execution" => %{
              "text" =>
                ~s({"summary":"bad json path","actions":[],"artifacts":[],"extra":"still visible"})
            }
          }
        )
      end)

    assert output =~ "response preview room=room-1 phase=proposal"
    assert output =~ "\"summary\":\"bad json path\""
    assert output =~ "completed room=room-1 phase=proposal status=failed actions=none"
  end
end
