defmodule JidoHiveClient.StatusTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Jido.Harness.RunRequest
  alias JidoHiveClient.Status

  test "client_start prints the selected websocket endpoint" do
    output =
      capture_io(fn ->
        Status.client_start(
          participant_id: "analyst",
          participant_role: "analyst",
          target_id: "target-analyst",
          executor: {JidoHiveClient.Executor.Session, [provider: :codex]},
          relay_topic: "relay:workspace-prod",
          workspace_id: "workspace-prod",
          url: "wss://jido-hive-server-test.app.nsai.online/socket/websocket"
        )
      end)

    assert output =~ "participant=analyst"
    assert output =~ "relay=relay:workspace-prod"
    assert output =~ "workspace=workspace-prod"
    assert output =~ "url=wss://jido-hive-server-test.app.nsai.online/socket/websocket"
    assert output =~ ~r/^\d{2}:\d{2}:\d{2}\.\d{3} \[jido_hive client\]/
  end

  test "relay_ready says the client is waiting for assignment relay work" do
    output =
      capture_io(fn ->
        Status.relay_ready(%{
          participant_id: "analyst",
          participant_role: "analyst",
          target_id: "target-analyst",
          capability_id: "workspace.exec.session",
          relay_topic: "relay:workspace-prod",
          workspace_id: "workspace-prod",
          socket_url: "wss://jido-hive-server-test.app.nsai.online/socket/websocket",
          executor: {JidoHiveClient.Executor.Session, [provider: :codex]}
        })
      end)

    assert output =~ "ready participant=analyst"
    assert output =~ "relay=relay:workspace-prod"
    assert output =~ "waiting_for=assignment.start"
    assert output =~ "url=wss://jido-hive-server-test.app.nsai.online/socket/websocket"
  end

  test "execution_started prints prompt previews for the pending llm call" do
    request =
      RunRequest.new!(%{
        prompt: "Execute the current assignment.\n{\"room_id\":\"room-1\"}",
        system_prompt: "Return strict JSON only.",
        allowed_tools: [],
        metadata: %{}
      })

    output =
      capture_io(fn ->
        Status.execution_started(
          %{
            "room_id" => "room-1",
            "phase" => "analysis"
          },
          [
            provider: :codex,
            model: "gpt-5.4",
            reasoning_effort: :low,
            executor: {JidoHiveClient.Executor.Session, [provider: :codex]},
            relay_topic: "relay:workspace-prod",
            workspace_id: "workspace-prod",
            url: "wss://jido-hive-server-test.app.nsai.online/socket/websocket",
            target_id: "target-analyst",
            participant_id: "analyst",
            participant_role: "analyst",
            socket_url: "wss://jido-hive-server-test.app.nsai.online/socket/websocket",
            capability_id: "workspace.exec.session"
          ],
          request
        )
      end)

    assert output =~
             "executing room=room-1 phase=analysis provider=codex assigned_role=analyst model=gpt-5.4"

    assert output =~ "system prompt preview room=room-1 phase=analysis"
    assert output =~ ~s(preview="Return strict JSON only.")
    assert output =~ "user prompt preview room=room-1 phase=analysis"

    assert output =~
             ~s(preview="Execute the current assignment. {\\\"room_id\\\":\\\"room-1\\\"}")
  end

  test "execution_finished prints a response preview before the summary" do
    output =
      capture_io(fn ->
        Status.execution_finished(
          %{
            "room_id" => "room-1",
            "phase" => "analysis"
          },
          %{
            "status" => "failed",
            "context_objects" => [],
            "execution" => %{
              "text" =>
                ~s({"summary":"bad json path","contribution_type":"reasoning","context_objects":[],"extra":"still visible"})
            }
          }
        )
      end)

    assert output =~ "response preview room=room-1 phase=analysis"
    assert output =~ ~s(preview="{\\\"summary\\\":\\\"bad json path\\\")
    assert output =~ "completed room=room-1 phase=analysis status=failed contribution=none"
  end
end
