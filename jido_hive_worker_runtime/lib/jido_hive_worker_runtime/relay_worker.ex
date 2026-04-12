defmodule JidoHiveWorkerRuntime.RelayWorker do
  @moduledoc false

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoHiveWorkerRuntime.Boundary.ProtocolCodec
  alias JidoHiveWorkerRuntime.{Runtime, Status}
  alias PhoenixClient.{Channel, Message, Socket}

  @join_retry_ms 200
  @default_room_refresh_interval_ms 2_000
  @default_contribution_submit_timeout_ms 30_000

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
    http_client = Keyword.get(opts, :http_client, JidoHiveWorkerRuntime.Boundary.ServerAPI.HTTP)
    executor = normalize_executor(Keyword.get(opts, :executor))
    {runtime, owned_runtime?} = ensure_runtime(opts, executor)
    socket_url = Keyword.fetch!(opts, :url)

    {:ok, socket} =
      socket_module.start_link(
        Keyword.merge(
          [
            url: socket_url,
            params: %{"client" => "jido_hive_worker_runtime"}
          ],
          Keyword.get(opts, :socket_opts, [])
        )
      )

    configured_room_ids =
      opts
      |> Keyword.get(:room_ids, [])
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    state = %{
      socket: socket,
      socket_module: socket_module,
      channel_module: channel_module,
      http_client: http_client,
      runtime: runtime,
      owned_runtime?: owned_runtime?,
      socket_url: socket_url,
      api_base_url: Keyword.get(opts, :api_base_url, ProtocolCodec.api_base_url(socket_url)),
      connection_state: :starting,
      configured_room_ids: configured_room_ids,
      discover_rooms?: Keyword.get(opts, :discover_rooms, MapSet.size(configured_room_ids) == 0),
      room_channels: %{},
      room_refresh_interval_ms:
        Keyword.get(opts, :room_refresh_interval_ms, @default_room_refresh_interval_ms),
      workspace_id: Keyword.get(opts, :workspace_id, "workspace-local"),
      user_id: Keyword.fetch!(opts, :user_id),
      participant_id: Keyword.fetch!(opts, :participant_id),
      participant_role: Keyword.fetch!(opts, :participant_role),
      target_id: Keyword.fetch!(opts, :target_id),
      capability_id: Keyword.fetch!(opts, :capability_id),
      workspace_root: Keyword.get(opts, :workspace_root, File.cwd!()),
      runtime_id: :asm,
      contribution_submit_timeout_ms: contribution_submit_timeout_ms(opts),
      executor: executor,
      opts: opts
    }

    Status.relay_connecting(state)
    _ = maybe_upsert_target(state)

    safe_runtime_update_connection(runtime, :starting, %{
      "url" => state.socket_url,
      "api_base_url" => state.api_base_url
    })

    send(self(), :ensure_joined)
    {:ok, state}
  end

  @impl true
  def handle_info(:ensure_joined, %{socket: socket, socket_module: socket_module} = state) do
    if socket_module.connected?(socket) do
      {:noreply, state |> sync_room_channels() |> schedule_room_refresh()}
    else
      {:noreply, waiting_for_socket(state)}
    end
  end

  def handle_info(:refresh_rooms, %{socket: socket, socket_module: socket_module} = state) do
    if socket_module.connected?(socket) do
      {:noreply, state |> sync_room_channels() |> schedule_room_refresh()}
    else
      {:noreply, waiting_for_socket(state)}
    end
  end

  @impl true
  def handle_info(
        %Message{event: "assignment.offer", topic: "room:" <> room_id, payload: payload},
        state
      ) do
    case ProtocolCodec.normalize_assignment_offer(payload) do
      {:ok, normalized_assignment} ->
        Status.assignment_received(normalized_assignment, state)

        publish_signal("client.assignment.received", %{
          assignment_id: normalized_assignment["id"],
          participant_id: state.participant_id,
          target_id: state.target_id,
          room_id: room_id
        })

        contribution =
          case execute_assignment(normalized_assignment, state) do
            {:ok, contribution} -> contribution
            {:error, reason} -> failed_contribution(normalized_assignment, reason)
          end
          |> Map.put_new("id", contribution_id(normalized_assignment, state))
          |> Map.put_new("room_id", normalized_assignment["room_id"])
          |> Map.put_new("assignment_id", normalized_assignment["id"])
          |> Map.put_new(
            "participant_id",
            normalized_assignment["participant_id"] || state.participant_id
          )

        case push_contribution(state, room_id, contribution) do
          {:ok, _reply} ->
            Status.result_published(normalized_assignment, contribution)

            safe_runtime_record_contribution_published(
              state.runtime,
              normalized_assignment,
              contribution
            )

            publish_signal("client.assignment.completed", %{
              assignment_id: normalized_assignment["id"],
              participant_id: state.participant_id,
              target_id: state.target_id,
              room_id: room_id
            })

          {:error, reason} ->
            Status.execution_failed(normalized_assignment, {:contribution_submit_failed, reason})

            safe_runtime_record_assignment_failed(
              state.runtime,
              normalized_assignment,
              {:contribution_submit_failed, reason}
            )

            publish_signal("client.assignment.failed", %{
              assignment_id: normalized_assignment["id"],
              participant_id: state.participant_id,
              target_id: state.target_id,
              room_id: room_id,
              reason: inspect(reason)
            })
        end

        {:noreply, state}

      {:error, reason} ->
        Status.execution_failed(%{"room_id" => room_id, "phase" => "unknown"}, reason)
        {:noreply, state}
    end
  end

  def handle_info(
        %Message{event: "room.event", topic: "room:" <> room_id, payload: payload},
        state
      ) do
    sequence =
      payload
      |> Map.get("data", %{})
      |> Map.get("sequence")

    next_state =
      if is_integer(sequence) do
        update_room_channel(state, room_id, fn room_state ->
          room_state
          |> Map.put(
            :last_seen_event_sequence,
            max(sequence, room_state.last_seen_event_sequence || 0)
          )
          |> Map.put(
            :current_event_sequence,
            max(sequence, room_state.current_event_sequence || 0)
          )
        end)
      else
        state
      end

    {:noreply, next_state}
  end

  def handle_info(%Message{event: event}, state) when event in ["phx_close", "phx_error"] do
    Status.relay_disconnected(state, event)
    safe_runtime_update_connection(state.runtime, :waiting_socket, %{"event" => event})
    Process.send_after(self(), :ensure_joined, @join_retry_ms)
    {:noreply, clear_room_channels(%{state | connection_state: :waiting_socket})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(
        _reason,
        %{
          socket: socket,
          socket_module: socket_module,
          runtime: runtime,
          owned_runtime?: owned_runtime?
        } = state
      ) do
    maybe_disconnect_runtime(runtime)
    clear_room_channels(state)
    _ = maybe_mark_target_offline(state)
    if is_pid(socket), do: socket_module.stop(socket)
    if owned_runtime? and is_pid(runtime), do: GenServer.stop(runtime)
    :ok
  end

  defp sync_room_channels(state) do
    case desired_room_ids(state) do
      {:ok, desired_room_ids} ->
        current_room_ids = Map.keys(state.room_channels) |> MapSet.new()

        state =
          current_room_ids
          |> MapSet.difference(desired_room_ids)
          |> Enum.reduce(state, &leave_room_channel(&2, &1))

        state =
          desired_room_ids
          |> MapSet.difference(current_room_ids)
          |> Enum.reduce(state, &join_room_channel(&2, &1))

        connection_payload = %{
          "url" => state.socket_url,
          "api_base_url" => state.api_base_url,
          "room_ids" => Enum.sort(Map.keys(state.room_channels))
        }

        Status.relay_ready(state)
        safe_runtime_update_connection(state.runtime, :ready, connection_payload)
        %{state | connection_state: :ready}

      {:error, reason} ->
        safe_runtime_update_connection(state.runtime, :waiting_socket, %{
          "reason" => inspect(reason)
        })

        schedule_join_retry(state, :waiting_socket, fn ->
          Status.relay_join_retry(state, reason)
        end)
    end
  end

  defp desired_room_ids(state) do
    with {:ok, discovered_room_ids} <- discovered_room_ids(state) do
      {:ok, MapSet.union(state.configured_room_ids, discovered_room_ids)}
    end
  end

  defp discovered_room_ids(%{discover_rooms?: false}), do: {:ok, MapSet.new()}

  defp discovered_room_ids(state) do
    with {:ok, rooms} <-
           state.http_client.list_rooms(state.api_base_url, state.participant_id) do
      room_ids =
        rooms
        |> Enum.reject(&terminal_room_resource?/1)
        |> Enum.map(&room_resource_id/1)
        |> Enum.filter(&is_binary/1)
        |> MapSet.new()

      {:ok, room_ids}
    end
  end

  defp join_room_channel(state, room_id) do
    last_seen_event_sequence =
      state.room_channels
      |> Map.get(room_id, %{})
      |> Map.get(:last_seen_event_sequence)

    case state.channel_module.join(
           state.socket,
           room_topic(room_id),
           ProtocolCodec.room_join_payload(state, last_seen_event_sequence)
         ) do
      {:ok, response, channel} ->
        case catch_up_room(state, room_id, channel, response, last_seen_event_sequence) do
          {:ok, caught_up_sequence} ->
            publish_signal("client.room.joined", %{
              target_id: state.target_id,
              room_id: room_id
            })

            put_room_channel(
              state,
              room_id,
              room_channel_state(channel, response, caught_up_sequence)
            )

          {:error, reason} ->
            _ = state.channel_module.leave(channel)
            retry_join(state, reason)
        end

      {:error, reason} ->
        retry_join(state, reason)
    end
  end

  defp catch_up_room(state, room_id, channel, response, last_seen_event_sequence) do
    current_sequence = current_event_sequence(response)
    catch_up_required = Map.get(response, "catch_up_required", false)

    if catch_up_required do
      target_sequence = Map.get(response, "catch_up_target_sequence", current_sequence)

      with {:ok, through_sequence} <-
             fetch_room_events_until(
               state,
               room_id,
               last_seen_event_sequence || 0,
               target_sequence
             ),
           {:ok, _reply} <-
             state.channel_module.push(
               channel,
               "session.caught_up",
               %{"through_sequence" => max(through_sequence, target_sequence)}
             ) do
        {:ok, max(through_sequence, target_sequence)}
      end
    else
      {:ok, max(last_seen_event_sequence || 0, current_sequence)}
    end
  end

  defp room_channel_state(channel, response, caught_up_sequence) do
    %{
      channel: channel,
      last_seen_event_sequence: caught_up_sequence,
      current_event_sequence: max(current_event_sequence(response), caught_up_sequence),
      caught_up: true
    }
  end

  defp retry_join(state, reason) do
    schedule_join_retry(state, :joining, fn -> Status.relay_join_retry(state, reason) end)
  end

  defp fetch_room_events_until(_state, _room_id, after_sequence, target_sequence)
       when after_sequence >= target_sequence do
    {:ok, after_sequence}
  end

  defp fetch_room_events_until(state, room_id, after_sequence, target_sequence) do
    with {:ok, events} <-
           state.http_client.list_room_events(state.api_base_url, room_id, after_sequence) do
      latest_sequence =
        events
        |> List.last()
        |> case do
          %{"sequence" => sequence} when is_integer(sequence) -> sequence
          _other -> after_sequence
        end

      cond do
        latest_sequence >= target_sequence ->
          {:ok, latest_sequence}

        events == [] ->
          {:ok, after_sequence}

        true ->
          fetch_room_events_until(state, room_id, latest_sequence, target_sequence)
      end
    end
  end

  defp push_contribution(state, room_id, contribution) do
    case Map.get(state.room_channels, room_id) do
      %{channel: channel} ->
        state.channel_module.push(
          channel,
          "contribution.submit",
          %{"data" => contribution},
          state.contribution_submit_timeout_ms
        )

      _other ->
        {:error, :room_channel_not_joined}
    end
  end

  defp leave_room_channel(state, room_id) do
    case Map.get(state.room_channels, room_id) do
      %{channel: channel} ->
        _ = state.channel_module.leave(channel)
        %{state | room_channels: Map.delete(state.room_channels, room_id)}

      _other ->
        state
    end
  end

  defp clear_room_channels(state) do
    Enum.reduce(Map.keys(state.room_channels), state, &leave_room_channel(&2, &1))
  end

  defp update_room_channel(state, room_id, fun) when is_function(fun, 1) do
    case Map.get(state.room_channels, room_id) do
      nil -> state
      room_state -> put_room_channel(state, room_id, fun.(room_state))
    end
  end

  defp put_room_channel(state, room_id, room_state) do
    %{state | room_channels: Map.put(state.room_channels, room_id, room_state)}
  end

  defp room_resource_id(%{"room" => %{"id" => room_id}}), do: room_id
  defp room_resource_id(%{room: %{id: room_id}}), do: room_id
  defp room_resource_id(_other), do: nil

  defp terminal_room_resource?(%{"room" => %{"status" => status}}),
    do: status in ["completed", "closed", "failed"]

  defp terminal_room_resource?(%{room: %{status: status}}),
    do: status in ["completed", "closed", "failed"]

  defp terminal_room_resource?(_other), do: false

  defp current_event_sequence(response) when is_map(response) do
    case Map.get(response, "current_event_sequence", 0) do
      sequence when is_integer(sequence) and sequence >= 0 -> sequence
      _other -> 0
    end
  end

  defp room_topic(room_id), do: "room:#{room_id}"

  defp normalize_executor({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_executor(module) when is_atom(module), do: {module, []}

  defp normalize_executor(nil) do
    {JidoHiveWorkerRuntime.Executor.Session, [provider: :codex]}
  end

  defp contribution_submit_timeout_ms(opts) do
    Keyword.get(
      opts,
      :contribution_submit_timeout_ms,
      Application.get_env(
        :jido_hive_worker_runtime,
        :relay_contribution_submit_timeout_ms,
        @default_contribution_submit_timeout_ms
      )
    )
  end

  defp contribution_id(assignment, state) do
    room_id = assignment["room_id"]
    assignment_id = assignment["id"]
    participant_id = assignment["participant_id"] || state.participant_id
    target_id = assignment["target_id"] || state.target_id

    if Enum.all?([room_id, assignment_id, participant_id, target_id], &is_binary/1) do
      stable_contribution_id([room_id, assignment_id, participant_id, target_id])
    else
      random_contribution_id()
    end
  end

  defp stable_contribution_id(components) do
    digest =
      components
      |> Enum.join(":")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "contrib-" <> String.slice(digest, 0, 24)
  end

  defp random_contribution_id do
    "contrib-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  end

  defp publish_signal(type, data) do
    signal = Signal.new!(type, data, source: "/jido_hive_worker_runtime/relay_worker")
    _ = Bus.publish(JidoHiveWorkerRuntime.SignalBus, [signal])
    :ok
  end

  defp waiting_for_socket(state) do
    safe_runtime_update_connection(state.runtime, :waiting_socket, %{"url" => state.socket_url})
    schedule_join_retry(state, :waiting_socket, fn -> Status.relay_waiting(state) end)
  end

  defp schedule_room_refresh(state) do
    Process.send_after(self(), :refresh_rooms, state.room_refresh_interval_ms)
    state
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
        "summary" => "runtime execution failed",
        "kind" => "reasoning",
        "status" => "failed",
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

  defp maybe_upsert_target(%{http_client: http_client, api_base_url: api_base_url} = state)
       when is_atom(http_client) do
    http_client.upsert_target(api_base_url, ProtocolCodec.target_registration_payload(state))
  rescue
    _error -> :ok
  end

  defp maybe_upsert_target(_state), do: :ok

  defp maybe_mark_target_offline(%{
         http_client: http_client,
         api_base_url: api_base_url,
         target_id: target_id
       })
       when is_atom(http_client) do
    http_client.mark_target_offline(api_base_url, target_id)
  rescue
    _error -> :ok
  end

  defp maybe_mark_target_offline(_state), do: :ok

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

  defp safe_runtime_record_assignment_failed(runtime, assignment, reason) do
    if runtime_available?(runtime) do
      _ = safe_runtime_call(fn -> Runtime.assignment_failed(runtime, assignment, reason) end)
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
