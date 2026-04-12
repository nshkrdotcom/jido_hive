defmodule JidoHiveWorkerRuntime.RelayWorkerTest do
  use ExUnit.Case, async: true

  alias JidoHiveWorkerRuntime.{RelayWorker, Runtime}
  alias PhoenixClient.Message

  @receive_timeout 500

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

  defmodule HttpStub do
    def list_rooms(_api_base_url, _participant_id), do: {:ok, []}
    def list_room_events(_api_base_url, _room_id, _after_sequence), do: {:ok, []}
    def upsert_target(_api_base_url, payload), do: {:ok, payload}
    def mark_target_offline(_api_base_url, _target_id), do: :ok
  end

  defmodule ChannelStub do
    def join(socket, topic, payload) do
      test_pid = Agent.get(socket, & &1.test_pid)
      send(test_pid, {:channel_joined, topic, payload})

      {:ok, channel} = Agent.start_link(fn -> %{test_pid: test_pid, topic: topic} end)
      {:ok, %{"current_event_sequence" => 0, "catch_up_required" => false}, channel}
    end

    def push(channel, event, payload) do
      test_pid = Agent.get(channel, & &1.test_pid)
      send(test_pid, {:channel_push, event, payload})
      {:ok, payload}
    end

    def push(channel, event, payload, timeout) do
      test_pid = Agent.get(channel, & &1.test_pid)
      send(test_pid, {:channel_push, event, payload, timeout})
      {:ok, payload}
    end

    def leave(channel), do: Agent.stop(channel)
  end

  defmodule RejectingContributionChannelStub do
    alias JidoHiveWorkerRuntime.RelayWorkerTest.ChannelStub

    def join(socket, topic, payload), do: ChannelStub.join(socket, topic, payload)

    def push(channel, event, payload) do
      case event do
        "contribution.submit" ->
          test_pid = Agent.get(channel, & &1.test_pid)
          send(test_pid, {:channel_push, "contribution.submit", payload})
          {:error, %{"error" => "scope_violation"}}

        _other ->
          ChannelStub.push(channel, event, payload)
      end
    end

    def push(channel, event, payload, timeout) do
      case event do
        "contribution.submit" ->
          test_pid = Agent.get(channel, & &1.test_pid)
          send(test_pid, {:channel_push, "contribution.submit", payload, timeout})
          {:error, %{"error" => "scope_violation"}}

        _other ->
          ChannelStub.push(channel, event, payload, timeout)
      end
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
      executor: {JidoHiveWorkerRuntime.Executor.Scripted, [provider: :codex, role: :analyst]},
      runtime_id: :asm
    ]
  end

  defp worker_opts(runtime, test_pid) do
    worker_opts(runtime, test_pid, ChannelStub, ["room-1"])
  end

  defp worker_opts(runtime, test_pid, channel_module, room_ids) do
    [
      url: "ws://127.0.0.1:4000/socket/websocket",
      api_base_url: "http://127.0.0.1:4000/api",
      room_ids: room_ids,
      workspace_id: "workspace-1",
      user_id: "user-1",
      participant_id: "participant-1",
      participant_role: "analyst",
      target_id: "target-1",
      capability_id: "capability-1",
      workspace_root: "/workspace",
      executor: {JidoHiveWorkerRuntime.Executor.Scripted, [provider: :codex, role: :analyst]},
      runtime: runtime,
      socket_module: SocketStub,
      channel_module: channel_module,
      http_client: HttpStub,
      socket_opts: [test_pid: test_pid]
    ]
  end

  defp assignment_offer(room_id \\ "room-1") do
    %{
      "data" => %{
        "id" => "asn-1",
        "room_id" => room_id,
        "participant_id" => "participant-1",
        "status" => "pending",
        "payload" => %{
          "objective" => "Design a substrate.",
          "phase" => "analysis",
          "context" => %{"brief" => "Design a substrate.", "context_objects" => []},
          "output_contract" => %{
            "allowed_contribution_types" => ["reasoning"],
            "allowed_object_types" => ["belief"],
            "allowed_relation_types" => ["derives_from"]
          },
          "executor" => %{"provider" => "codex", "workspace_root" => "/workspace"}
        },
        "meta" => %{
          "participant_meta" => %{
            "role" => "analyst",
            "target_id" => "target-1",
            "capability_id" => "capability-1"
          }
        }
      }
    }
  end

  setup do
    {:ok, runtime} = start_supervised({Runtime, runtime_opts()})
    [runtime: runtime]
  end

  test "joins canonical room topics with participant metadata", %{runtime: runtime} do
    {:ok, _worker} = RelayWorker.start_link(worker_opts(runtime, self()))

    assert_receive {:channel_joined, "room:room-1", payload}, @receive_timeout
    assert get_in(payload, ["session", "mode"]) == "participant"
    assert get_in(payload, ["participant", "id"]) == "participant-1"
    assert get_in(payload, ["participant", "kind"]) == "agent"
    assert get_in(payload, ["participant", "meta", "target_id"]) == "target-1"
    assert get_in(payload, ["participant", "meta", "workspace_root"]) == "/workspace"
  end

  test "joins many room topics over one socket connection", %{runtime: runtime} do
    {:ok, _worker} =
      RelayWorker.start_link(worker_opts(runtime, self(), ChannelStub, ["room-1", "room-2"]))

    assert_receive {:channel_joined, "room:room-1", _payload}, @receive_timeout
    assert_receive {:channel_joined, "room:room-2", _payload}, @receive_timeout
  end

  test "executes an inbound assignment offer and publishes contribution.submit", %{
    runtime: runtime
  } do
    {:ok, worker} =
      RelayWorker.start_link(
        worker_opts(runtime, self()) ++ [contribution_submit_timeout_ms: 12_345]
      )

    await_handshake()

    send(worker, %Message{
      topic: "room:room-1",
      event: "assignment.offer",
      payload: assignment_offer()
    })

    assert_receive {:channel_push, "contribution.submit", %{"data" => contribution}, 12_345},
                   @receive_timeout

    assert contribution["assignment_id"] == "asn-1"
    assert contribution["kind"] == "reasoning"
    assert String.starts_with?(contribution["id"], "contrib-")
    assert Runtime.snapshot(runtime).metrics.assignments_completed == 1
  end

  test "retries room joins after a websocket disconnect event", %{runtime: runtime} do
    {:ok, worker} = RelayWorker.start_link(worker_opts(runtime, self()))
    await_handshake()

    send(worker, %Message{event: "phx_close", payload: %{}})

    assert_reconnecting(runtime)
    assert_receive {:channel_joined, "room:room-1", _payload}, 500
    assert_runtime_ready(runtime)
  end

  test "marks the assignment failed when contribution submission is rejected", %{runtime: runtime} do
    {:ok, worker} =
      RelayWorker.start_link(
        worker_opts(runtime, self(), RejectingContributionChannelStub, ["room-1"])
      )

    await_handshake()

    send(worker, %Message{
      topic: "room:room-1",
      event: "assignment.offer",
      payload: assignment_offer()
    })

    assert_receive {:channel_push, "contribution.submit", %{"data" => _contribution}, 30_000},
                   @receive_timeout

    assert Process.alive?(worker)
    assert_assignment_failed(runtime)
  end

  defp await_handshake do
    assert_receive {:channel_joined, "room:room-1", _payload}, @receive_timeout
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

  defp assert_reconnecting(runtime, attempts \\ 10)

  defp assert_reconnecting(runtime, attempts) when attempts > 0 do
    if Runtime.snapshot(runtime).connection_status in [:waiting_socket, :ready] do
      :ok
    else
      Process.sleep(20)
      assert_reconnecting(runtime, attempts - 1)
    end
  end

  defp assert_reconnecting(_runtime, 0) do
    flunk("runtime did not enter reconnecting state")
  end

  defp assert_assignment_failed(runtime, attempts \\ 10)

  defp assert_assignment_failed(runtime, attempts) when attempts > 0 do
    snapshot = Runtime.snapshot(runtime)

    if snapshot.metrics.assignments_failed == 1 and snapshot.connection_status == :ready do
      :ok
    else
      Process.sleep(20)
      assert_assignment_failed(runtime, attempts - 1)
    end
  end

  defp assert_assignment_failed(_runtime, 0) do
    flunk("runtime did not record the rejected contribution as a failed assignment")
  end
end
