defmodule JidoHiveClient.RelayWorker do
  @moduledoc false

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoHiveClient.Status
  alias PhoenixClient.{Channel, Message, Socket}

  @join_retry_ms 200

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, Keyword.get(opts, :target_id, __MODULE__)),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok, socket} =
      Socket.start_link(
        url: Keyword.fetch!(opts, :url),
        params: %{"client" => "jido_hive_client"}
      )

    state = %{
      socket: socket,
      channel: nil,
      socket_url: Keyword.fetch!(opts, :url),
      connection_state: :starting,
      relay_topic: Keyword.fetch!(opts, :relay_topic),
      workspace_id: Keyword.fetch!(opts, :workspace_id),
      user_id: Keyword.fetch!(opts, :user_id),
      participant_id: Keyword.fetch!(opts, :participant_id),
      participant_role: Keyword.fetch!(opts, :participant_role),
      target_id: Keyword.fetch!(opts, :target_id),
      capability_id: Keyword.fetch!(opts, :capability_id),
      workspace_root: Keyword.get(opts, :workspace_root, File.cwd!()),
      executor: normalize_executor(Keyword.get(opts, :executor)),
      opts: opts
    }

    Status.relay_connecting(state)
    send(self(), :ensure_joined)
    {:ok, state}
  end

  @impl true
  def handle_info(:ensure_joined, %{socket: socket, channel: nil} = state) do
    case Socket.connected?(socket) do
      true -> join_relay_channel(state)
      false -> {:noreply, waiting_for_socket(state)}
    end
  end

  def handle_info(:ensure_joined, state), do: {:noreply, state}

  @impl true
  def handle_info(%Message{event: "job.start", payload: job}, %{channel: channel} = state) do
    Status.job_received(job, state)

    publish_signal("client.job.received", %{
      job_id: job["job_id"],
      participant_id: state.participant_id,
      target_id: state.target_id
    })

    outbound =
      case execute_job(job, state) do
        {:ok, result} ->
          result

        {:error, reason} ->
          %{
            "job_id" => job["job_id"],
            "status" => "failed",
            "summary" => "runtime execution failed",
            "actions" => [],
            "tool_events" => [],
            "events" => [],
            "approvals" => [],
            "artifacts" => [],
            "execution" => %{
              "status" => "failed",
              "error" => %{"reason" => inspect(reason)}
            }
          }
      end
      |> Map.put_new("room_id", job["room_id"])
      |> Map.put_new("target_id", state.target_id)
      |> Map.put_new("capability_id", state.capability_id)
      |> Map.put_new("participant_id", job["participant_id"] || state.participant_id)
      |> Map.put_new("participant_role", job["participant_role"] || state.participant_role)

    {:ok, _} = Channel.push(channel, "job.result", outbound)
    Status.result_published(job, outbound)

    publish_signal("client.job.completed", %{
      job_id: job["job_id"],
      participant_id: state.participant_id,
      target_id: state.target_id
    })

    {:noreply, state}
  end

  def handle_info(%Message{event: event}, state) when event in ["phx_close", "phx_error"] do
    Status.relay_disconnected(state, event)
    Process.send_after(self(), :ensure_joined, @join_retry_ms)
    {:noreply, %{state | channel: nil, connection_state: :waiting_socket}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{channel: channel, socket: socket}) do
    if is_pid(channel), do: Channel.leave(channel)
    if is_pid(socket), do: Socket.stop(socket)
    :ok
  end

  defp execute_job(job, %{executor: {module, executor_opts}}) do
    module.run(job, executor_opts)
  end

  defp normalize_executor({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_executor(module) when is_atom(module), do: {module, []}

  defp normalize_executor(nil) do
    {JidoHiveClient.Executor.Session, [provider: :codex]}
  end

  defp hello_payload(state) do
    %{
      "workspace_id" => state.workspace_id,
      "user_id" => state.user_id,
      "participant_id" => state.participant_id,
      "participant_role" => state.participant_role,
      "client_version" => "0.1.0"
    }
  end

  defp target_payload(state) do
    %{
      "workspace_id" => state.workspace_id,
      "user_id" => state.user_id,
      "participant_id" => state.participant_id,
      "participant_role" => state.participant_role,
      "target_id" => state.target_id,
      "capability_id" => state.capability_id,
      "runtime_driver" => "asm",
      "provider" => "codex",
      "workspace_root" => state.workspace_root
    }
  end

  defp publish_signal(type, data) do
    signal = Signal.new!(type, data, source: "/jido_hive_client/relay_worker")
    _ = Bus.publish(JidoHiveClient.SignalBus, [signal])
    :ok
  end

  defp join_relay_channel(state) do
    case Channel.join(state.socket, state.relay_topic, %{"workspace_id" => state.workspace_id}) do
      {:ok, _response, channel} ->
        {:ok, _} = Channel.push(channel, "relay.hello", hello_payload(state))
        {:ok, _} = Channel.push(channel, "target.upsert", target_payload(state))

        Status.relay_ready(state)

        publish_signal("client.relay.joined", %{
          target_id: state.target_id,
          topic: state.relay_topic
        })

        {:noreply, %{state | channel: channel, connection_state: :joined}}

      {:error, reason} ->
        {:noreply,
         schedule_join_retry(state, :join_retry, fn -> Status.relay_join_retry(state, reason) end)}
    end
  end

  defp waiting_for_socket(state) do
    schedule_join_retry(state, :waiting_socket, fn -> Status.relay_waiting(state) end)
  end

  defp schedule_join_retry(state, connection_state, emit) when is_function(emit, 0) do
    state = maybe_transition(state, connection_state, emit)
    Process.send_after(self(), :ensure_joined, @join_retry_ms)
    state
  end

  defp maybe_transition(%{connection_state: new_state} = state, new_state, _emit), do: state

  defp maybe_transition(state, new_state, emit) when is_function(emit, 0) do
    emit.()
    %{state | connection_state: new_state}
  end
end
