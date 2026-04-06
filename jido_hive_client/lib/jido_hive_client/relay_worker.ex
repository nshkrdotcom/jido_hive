defmodule JidoHiveClient.RelayWorker do
  @moduledoc false

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoHiveClient.Boundary.ProtocolCodec
  alias JidoHiveClient.{Runtime, Status}
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

    socket_module = Keyword.get(opts, :socket_module, Socket)
    channel_module = Keyword.get(opts, :channel_module, Channel)
    executor = normalize_executor(Keyword.get(opts, :executor))
    {runtime, owned_runtime?} = ensure_runtime(opts, executor)

    {:ok, socket} =
      socket_module.start_link(
        Keyword.merge(
          [
            url: Keyword.fetch!(opts, :url),
            params: %{"client" => "jido_hive_client"}
          ],
          Keyword.get(opts, :socket_opts, [])
        )
      )

    state = %{
      socket: socket,
      socket_module: socket_module,
      channel_module: channel_module,
      runtime: runtime,
      owned_runtime?: owned_runtime?,
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
      runtime_id: :asm,
      executor: executor,
      opts: opts
    }

    Status.relay_connecting(state)

    safe_runtime_update_connection(runtime, :starting, %{
      "url" => state.socket_url,
      "relay_topic" => state.relay_topic
    })

    send(self(), :ensure_joined)
    {:ok, state}
  end

  @impl true
  def handle_info(
        :ensure_joined,
        %{socket: socket, socket_module: socket_module, channel: nil} = state
      ) do
    case socket_module.connected?(socket) do
      true ->
        safe_runtime_update_connection(state.runtime, :joining, %{
          "relay_topic" => state.relay_topic
        })

        join_relay_channel(state)

      false ->
        {:noreply, waiting_for_socket(state)}
    end
  end

  def handle_info(:ensure_joined, state), do: {:noreply, state}

  @impl true
  def handle_info(
        %Message{event: "assignment.start", payload: assignment},
        %{channel: channel} = state
      ) do
    case ProtocolCodec.normalize_assignment_start(assignment) do
      {:ok, normalized_assignment} ->
        Status.assignment_received(normalized_assignment, state)

        publish_signal("client.assignment.received", %{
          assignment_id: normalized_assignment["assignment_id"],
          participant_id: state.participant_id,
          target_id: state.target_id
        })

        contribution =
          case execute_assignment(normalized_assignment, state) do
            {:ok, contribution} -> contribution
            {:error, reason} -> failed_contribution(normalized_assignment, reason)
          end
          |> Map.put_new("room_id", normalized_assignment["room_id"])
          |> Map.put_new("assignment_id", normalized_assignment["assignment_id"])
          |> Map.put_new("target_id", state.target_id)
          |> Map.put_new("capability_id", state.capability_id)
          |> Map.put_new(
            "participant_id",
            normalized_assignment["participant_id"] || state.participant_id
          )
          |> Map.put_new(
            "participant_role",
            normalized_assignment["participant_role"] || state.participant_role
          )

        {:ok, _} = state.channel_module.push(channel, "contribution.submit", contribution)
        Status.result_published(normalized_assignment, contribution)

        safe_runtime_record_contribution_published(
          state.runtime,
          normalized_assignment,
          contribution
        )

        publish_signal("client.assignment.completed", %{
          assignment_id: normalized_assignment["assignment_id"],
          participant_id: state.participant_id,
          target_id: state.target_id
        })

        {:noreply, state}

      {:error, reason} ->
        Status.execution_failed(%{"room_id" => "unknown", "phase" => "unknown"}, reason)
        {:noreply, state}
    end
  end

  def handle_info(%Message{event: event}, state) when event in ["phx_close", "phx_error"] do
    Status.relay_disconnected(state, event)
    safe_runtime_update_connection(state.runtime, :waiting_socket, %{"event" => event})
    Process.send_after(self(), :ensure_joined, @join_retry_ms)
    {:noreply, %{state | channel: nil, connection_state: :waiting_socket}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{
        channel: channel,
        socket: socket,
        channel_module: channel_module,
        socket_module: socket_module,
        runtime: runtime,
        owned_runtime?: owned_runtime?
      }) do
    maybe_disconnect_runtime(runtime)
    if is_pid(channel), do: channel_module.leave(channel)
    if is_pid(socket), do: socket_module.stop(socket)
    if owned_runtime? and is_pid(runtime), do: GenServer.stop(runtime)
    :ok
  end

  defp normalize_executor({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_executor(module) when is_atom(module), do: {module, []}

  defp normalize_executor(nil) do
    {JidoHiveClient.Executor.Session, [provider: :codex]}
  end

  defp publish_signal(type, data) do
    signal = Signal.new!(type, data, source: "/jido_hive_client/relay_worker")
    _ = Bus.publish(JidoHiveClient.SignalBus, [signal])
    :ok
  end

  defp join_relay_channel(state) do
    case state.channel_module.join(state.socket, state.relay_topic, %{
           "workspace_id" => state.workspace_id
         }) do
      {:ok, _response, channel} ->
        {:ok, _} =
          state.channel_module.push(channel, "relay.hello", ProtocolCodec.hello_payload(state))

        {:ok, _} =
          state.channel_module.push(
            channel,
            "participant.upsert",
            ProtocolCodec.participant_payload(state)
          )

        Status.relay_ready(state)

        safe_runtime_update_connection(state.runtime, :ready, %{
          "url" => state.socket_url,
          "relay_topic" => state.relay_topic
        })

        publish_signal("client.relay.joined", %{
          target_id: state.target_id,
          topic: state.relay_topic
        })

        {:noreply, %{state | channel: channel, connection_state: :joined}}

      {:error, reason} ->
        safe_runtime_update_connection(state.runtime, :waiting_socket, %{
          "reason" => inspect(reason)
        })

        {:noreply,
         schedule_join_retry(state, :join_retry, fn -> Status.relay_join_retry(state, reason) end)}
    end
  end

  defp waiting_for_socket(state) do
    safe_runtime_update_connection(state.runtime, :waiting_socket, %{"url" => state.socket_url})
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

  defp failed_contribution(assignment, reason) do
    ProtocolCodec.normalize_contribution(
      %{
        "status" => "failed",
        "summary" => "runtime execution failed",
        "execution" => %{
          "status" => "failed",
          "error" => %{"reason" => inspect(reason)}
        }
      },
      assignment
    )
  end

  defp runtime_opts(opts, executor) do
    opts
    |> Keyword.take([
      :workspace_id,
      :user_id,
      :participant_id,
      :participant_role,
      :target_id,
      :capability_id,
      :workspace_root
    ])
    |> Keyword.put(:executor, executor)
    |> Keyword.put(:runtime_id, :asm)
  end

  defp ensure_runtime(opts, executor) do
    runtime_opts = runtime_opts(opts, executor)

    case Keyword.get(opts, :runtime) do
      nil ->
        {:ok, runtime} = Runtime.start_link(runtime_opts)
        {runtime, true}

      runtime ->
        :ok = Runtime.configure(runtime, runtime_opts)
        {runtime, false}
    end
  end

  defp maybe_disconnect_runtime(runtime) when is_pid(runtime) do
    if Process.alive?(runtime), do: safe_runtime_call(fn -> Runtime.disconnect(runtime) end)
    :ok
  end

  defp maybe_disconnect_runtime(runtime) when is_atom(runtime) do
    if Process.whereis(runtime), do: safe_runtime_call(fn -> Runtime.disconnect(runtime) end)
    :ok
  end

  defp execute_assignment(assignment, %{runtime: runtime, executor: {module, executor_opts}})
       when is_map(assignment) and is_atom(module) and is_list(executor_opts) do
    runtime_result(runtime, assignment) || module.run(assignment, executor_opts)
  end

  defp safe_runtime_update_connection(runtime, status, payload) do
    if runtime_available?(runtime) do
      _ = safe_runtime_call(fn -> Runtime.update_connection(runtime, status, payload) end)
    end

    :ok
  end

  defp safe_runtime_record_contribution_published(runtime, assignment, contribution) do
    if runtime_available?(runtime) do
      _ =
        safe_runtime_call(fn ->
          Runtime.record_contribution_published(runtime, assignment, contribution)
        end)
    end

    :ok
  end

  defp safe_runtime_call(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  catch
    :exit, reason -> {:error, reason}
  end

  defp runtime_result(runtime, assignment) do
    with true <- runtime_available?(runtime),
         {:ok, result} <- safe_runtime_call(fn -> Runtime.run_assignment(runtime, assignment) end) do
      result
    else
      _other -> nil
    end
  end

  defp runtime_available?(runtime) when is_pid(runtime), do: Process.alive?(runtime)
  defp runtime_available?(runtime) when is_atom(runtime), do: not is_nil(Process.whereis(runtime))
end
