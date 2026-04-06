defmodule JidoHiveClient.RelayWorkerTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.{RelayWorker, Runtime}
  alias PhoenixClient.Message

  defmodule SocketStub do
    def start_link(opts) do
      Agent.start_link(fn ->
        %{
          connected?: Keyword.get(opts, :connected, true),
          test_pid: Keyword.fetch!(opts, :test_pid)
        }
      end)
    end

    def connected?(pid), do: Agent.get(pid, & &1.connected?)
    def stop(pid), do: Agent.stop(pid)
  end

  defmodule ChannelStub do
    def join(socket, topic, payload) do
      test_pid = Agent.get(socket, & &1.test_pid)
      send(test_pid, {:channel_joined, topic, payload})

      {:ok, channel} = Agent.start_link(fn -> %{test_pid: test_pid} end)
      {:ok, %{"status" => "ok"}, channel}
    end

    def push(channel, event, payload) do
      test_pid = Agent.get(channel, & &1.test_pid)
      send(test_pid, {:channel_push, event, payload})
      {:ok, payload}
    end

    def leave(channel), do: Agent.stop(channel)
  end

  defp runtime_opts do
    [
      workspace_id: "workspace-1",
      user_id: "user-1",
      participant_id: "participant-1",
      participant_role: "analyst",
      target_id: "target-1",
      capability_id: "capability-1",
      workspace_root: "/workspace",
      executor: {JidoHiveClient.Executor.Scripted, [provider: :codex, role: :analyst]},
      runtime_id: :asm
    ]
  end

  defp worker_opts(runtime, test_pid) do
    [
      url: "ws://127.0.0.1:4000/socket/websocket",
      relay_topic: "relay:workspace-1",
      workspace_id: "workspace-1",
      user_id: "user-1",
      participant_id: "participant-1",
      participant_role: "analyst",
      target_id: "target-1",
      capability_id: "capability-1",
      workspace_root: "/workspace",
      executor: {JidoHiveClient.Executor.Scripted, [provider: :codex, role: :analyst]},
      runtime: runtime,
      socket_module: SocketStub,
      channel_module: ChannelStub,
      socket_opts: [test_pid: test_pid]
    ]
  end

  defp assignment_payload do
    %{
      "assignment_id" => "asn-1",
      "room_id" => "room-1",
      "participant_id" => "participant-1",
      "participant_role" => "analyst",
      "target_id" => "target-1",
      "capability_id" => "capability-1",
      "session" => %{"provider" => "codex"},
      "contribution_contract" => %{
        "allowed_contribution_types" => ["reasoning"],
        "allowed_object_types" => ["belief"],
        "allowed_relation_types" => ["derives_from"]
      },
      "context_view" => %{"brief" => "Design a substrate.", "context_objects" => []}
    }
  end

  setup do
    {:ok, runtime} = start_supervised({Runtime, runtime_opts()})
    [runtime: runtime]
  end

  test "registers with the relay by joining then sending hello and participant upsert", %{
    runtime: runtime
  } do
    {:ok, _worker} = RelayWorker.start_link(worker_opts(runtime, self()))

    assert_receive {:channel_joined, "relay:workspace-1", %{"workspace_id" => "workspace-1"}}
    assert_receive {:channel_push, "relay.hello", hello_payload}
    assert_receive {:channel_push, "participant.upsert", participant_payload}

    assert hello_payload["participant_id"] == "participant-1"
    assert participant_payload["target_id"] == "target-1"
    assert participant_payload["workspace_root"] == "/workspace"
  end

  test "executes an inbound assignment and publishes contribution.submit", %{runtime: runtime} do
    {:ok, worker} = RelayWorker.start_link(worker_opts(runtime, self()))
    await_handshake()

    send(worker, %Message{event: "assignment.start", payload: assignment_payload()})

    assert_receive {:channel_push, "contribution.submit", contribution}
    assert contribution["assignment_id"] == "asn-1"
    assert contribution["status"] == "completed"
    assert Runtime.snapshot(runtime).metrics.assignments_completed == 1
  end

  test "retries join after a relay disconnect event", %{runtime: runtime} do
    {:ok, worker} = RelayWorker.start_link(worker_opts(runtime, self()))
    await_handshake()

    send(worker, %Message{event: "phx_close", payload: %{}})

    assert Runtime.snapshot(runtime).connection_status in [:waiting_socket, :joining]
    assert_receive {:channel_joined, "relay:workspace-1", %{"workspace_id" => "workspace-1"}}, 500
    assert_receive {:channel_push, "relay.hello", _hello_payload}
    assert_receive {:channel_push, "participant.upsert", _participant_payload}
    assert_runtime_ready(runtime)
  end

  defp await_handshake do
    assert_receive {:channel_joined, "relay:workspace-1", %{"workspace_id" => "workspace-1"}}
    assert_receive {:channel_push, "relay.hello", _payload}
    assert_receive {:channel_push, "participant.upsert", _payload}
    :ok
  end

  defp assert_runtime_ready(runtime, attempts \\ 10)

  defp assert_runtime_ready(runtime, attempts) when attempts > 0 do
    if Runtime.snapshot(runtime).connection_status == :ready do
      :ok
    else
      Process.sleep(20)
      assert_runtime_ready(runtime, attempts - 1)
    end
  end

  defp assert_runtime_ready(_runtime, 0) do
    flunk("runtime did not return to :ready")
  end
end
