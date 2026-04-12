defmodule JidoHiveClient.Embedded do
  @moduledoc false

  use GenServer

  alias JidoHiveClient.AgentBackends.Mock
  alias JidoHiveClient.Boundary.RoomApi.Http, as: HttpRoomApi
  alias JidoHiveClient.ChatInput
  alias JidoHiveClient.DebugTrace
  alias JidoHiveClient.Interceptor
  alias JidoHiveClient.Operation
  alias JidoHiveClient.Polling
  alias JidoHiveClient.{SessionEventLog, SessionState}
  alias JidoHiveClient.Transport.HTTP, as: TransportHTTP

  @default_poll_interval_ms Polling.default_interval_ms()
  @room_not_found_retry_limit 3
  @timeline_limit 200
  @operation_history_limit 25

  @type snapshot :: %{
          room_id: String.t(),
          participant: map(),
          session_state: map(),
          timeline: [map()],
          context_objects: [map()],
          next_cursor: String.t() | nil,
          last_sync_at: DateTime.t() | nil,
          last_error: term(),
          operations: [map()],
          transport: map()
        }

  defstruct [
    :session_state,
    :event_log,
    :room_api,
    :room_api_opts,
    :agent_backend,
    :agent_backend_opts,
    :room_id,
    :participant,
    :last_sync_at,
    :last_error,
    room_snapshot: %{},
    subscribers: MapSet.new(),
    polling: %{
      timer_ref: nil,
      interval_ms: @default_poll_interval_ms,
      next_delay_ms: @default_poll_interval_ms,
      failure_count: 0,
      idle_count: 0,
      halted_reason: nil
    },
    timeline: [],
    context_objects: [],
    next_cursor: nil,
    sync_task_pid: nil,
    sync_task_ref: nil,
    sync_waiters: [],
    sync_record_event: false,
    sync_force_full: false,
    sync_queued: false,
    sync_queued_record_event: false,
    sync_queued_force_full: false,
    queued_sync_waiters: [],
    submit_operations: %{},
    submit_order: [],
    submit_tasks: %{}
  ]

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, Keyword.get(opts, :name, __MODULE__)),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts)
    end
  end

  @spec snapshot(pid() | atom()) :: snapshot()
  def snapshot(server), do: GenServer.call(server, :snapshot)

  @spec subscribe(pid() | atom()) :: :ok
  def subscribe(server), do: GenServer.call(server, :subscribe)

  @spec submit_chat(pid() | atom(), map()) :: {:ok, map()} | {:error, term()}
  def submit_chat(server, attrs) when is_map(attrs),
    do: GenServer.call(server, {:submit_chat, attrs}, 15_000)

  @spec submit_chat_async(pid() | atom(), map()) :: {:ok, map()} | {:error, term()}
  def submit_chat_async(server, attrs) when is_map(attrs),
    do: GenServer.call(server, {:submit_chat_async, attrs}, 5_000)

  @spec accept_context(pid() | atom(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def accept_context(server, context_id, attrs \\ %{})
      when is_binary(context_id) and is_map(attrs) do
    GenServer.call(server, {:accept_context, context_id, attrs}, 15_000)
  end

  @spec refresh(pid() | atom()) :: {:ok, snapshot()} | {:error, term()}
  def refresh(server), do: GenServer.call(server, :refresh, 15_000)

  @spec shutdown(pid() | atom()) :: :ok
  def shutdown(server), do: GenServer.stop(server)

  @impl true
  def init(opts) do
    participant = participant_from_opts(opts)
    session_state = new_session_state(opts, participant)
    {room_api, room_api_opts} = normalize_room_api(Keyword.get(opts, :room_api))
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)

    {agent_backend, agent_backend_opts} =
      normalize_agent_backend(Keyword.get(opts, :agent_backend))

    state =
      %__MODULE__{
        session_state: session_state,
        event_log: SessionEventLog.new(limit: Keyword.get(opts, :event_limit, 200)),
        room_api: room_api,
        room_api_opts:
          [base_url: Keyword.get(opts, :api_base_url)]
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Keyword.merge(room_api_opts),
        agent_backend: agent_backend,
        agent_backend_opts: agent_backend_opts,
        room_id: Keyword.fetch!(opts, :room_id),
        participant: participant,
        polling: new_polling_state(poll_interval_ms)
      }
      |> update_session_connection(:ready, %{
        "mode" => "embedded",
        "room_id" => Keyword.fetch!(opts, :room_id)
      })
      |> record_session_event(%{
        type: "embedded.started",
        room_id: Keyword.fetch!(opts, :room_id),
        payload: participant
      })

    {:ok, schedule_poll(state, 0)}
  end

  @impl true
  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply, current_snapshot(state), state}
  end

  def handle_call(:subscribe, {pid, _tag}, %__MODULE__{} = state) do
    next_state = %{state | subscribers: MapSet.put(state.subscribers, pid)}
    maybe_push_subscriber_snapshot(pid, next_state)
    {:reply, :ok, next_state}
  end

  def handle_call(:refresh, from, %__MODULE__{} = state) do
    {:noreply, request_sync(state, true, [from], true)}
  end

  def handle_call({:submit_chat, attrs}, _from, %__MODULE__{} = state) do
    DebugTrace.emit(:info, "room_session.submit_chat.started", %{
      room_id: state.room_id,
      participant_id: state.participant.participant_id,
      chars: attrs |> Map.get(:text, Map.get(attrs, "text", "")) |> to_string() |> String.length()
    })

    operation_id =
      Map.get(attrs, :operation_id) || Map.get(attrs, "operation_id") ||
        Operation.new_id("room_submit")

    with {:ok, contribution} <- prepare_chat_contribution(attrs, state),
         {:ok, _response} <-
           state.room_api.submit_contribution(
             room_api_submit_opts(state, operation_id),
             state.room_id,
             contribution
           ) do
      DebugTrace.emit(:info, "room_session.submit_chat.completed", %{
        room_id: state.room_id,
        participant_id: state.participant.participant_id,
        contribution_type: contribution_kind(contribution),
        context_count: contribution_context_count(contribution)
      })

      send(self(), {:sync_room_async, true})

      {:reply, {:ok, contribution},
       state
       |> Map.put(:last_error, nil)
       |> clear_session_error()
       |> record_session_event(%{
         type: "embedded.chat.submitted",
         room_id: state.room_id,
         payload: %{
           "operation_id" => operation_id,
           "summary" => contribution_summary(contribution),
           "context_count" => contribution_context_count(contribution)
         }
       })}
    else
      {:error, reason} ->
        DebugTrace.emit(:error, "room_session.submit_chat.failed", %{
          room_id: state.room_id,
          participant_id: state.participant.participant_id,
          reason: inspect(reason)
        })

        {:reply, {:error, reason},
         state
         |> Map.put(:last_error, reason)
         |> put_session_error(reason)
         |> record_session_event(%{
           type: "embedded.chat.failed",
           room_id: state.room_id,
           payload: %{"reason" => inspect(reason)}
         })}
    end
  end

  def handle_call({:submit_chat_async, attrs}, _from, %__MODULE__{} = state) do
    operation_id =
      Map.get(attrs, :operation_id) || Map.get(attrs, "operation_id") ||
        Operation.new_id("room_submit")

    text =
      attrs
      |> Map.get(:text, Map.get(attrs, "text", ""))
      |> to_string()

    operation =
      new_submit_operation(operation_id, text)
      |> Map.put("participant_id", state.participant.participant_id)

    DebugTrace.emit(:info, "room_session.submit_chat.accepted", %{
      room_id: state.room_id,
      participant_id: state.participant.participant_id,
      operation_id: operation_id,
      chars: String.length(text)
    })

    {:reply, {:ok, operation},
     state
     |> put_submit_operation(operation)
     |> record_session_event(%{
       type: "embedded.chat.accepted",
       room_id: state.room_id,
       payload: %{
         "operation_id" => operation_id,
         "chars" => String.length(text)
       }
     })
     |> start_submit_task(operation_id, attrs)}
  end

  def handle_call({:accept_context, context_id, attrs}, _from, %__MODULE__{} = state) do
    case Enum.find(state.context_objects, &context_id_matches?(&1, context_id)) do
      nil ->
        {:reply, {:error, :context_object_not_found}, state}

      context_object ->
        DebugTrace.emit(:info, "room_session.accept_context.started", %{
          room_id: state.room_id,
          participant_id: state.participant.participant_id,
          context_id: context_id
        })

        contribution = acceptance_contribution(context_object, attrs, state)

        case state.room_api.submit_contribution(
               room_api_submit_opts(state, Operation.new_id("room_accept")),
               state.room_id,
               contribution
             ) do
          {:ok, _response} ->
            DebugTrace.emit(:info, "room_session.accept_context.completed", %{
              room_id: state.room_id,
              participant_id: state.participant.participant_id,
              context_id: context_id
            })

            send(self(), {:sync_room_async, true})

            {:reply, {:ok, contribution},
             state
             |> Map.put(:last_error, nil)
             |> clear_session_error()
             |> record_session_event(%{
               type: "embedded.context.accepted",
               room_id: state.room_id,
               payload: %{"context_id" => context_id}
             })}

          {:error, reason} ->
            DebugTrace.emit(:error, "room_session.accept_context.failed", %{
              room_id: state.room_id,
              participant_id: state.participant.participant_id,
              context_id: context_id,
              reason: inspect(reason)
            })

            {:reply, {:error, reason},
             state
             |> Map.put(:last_error, reason)
             |> put_session_error(reason)}
        end
    end
  end

  @impl true
  def handle_info({:sync_room_async, record_event?}, %__MODULE__{} = state) do
    {:noreply, request_sync(state, record_event?, [], false)}
  end

  def handle_info(:poll, %__MODULE__{} = state), do: handle_poll(clear_poll_timer(state))

  def handle_info(
        {:poll, token},
        %__MODULE__{polling: %{timer_ref: {_timer_ref, token}}} = state
      ),
      do: handle_poll(clear_poll_timer(state))

  def handle_info({:poll, _stale_token}, %__MODULE__{} = state), do: {:noreply, state}

  def handle_info(
        {:sync_result, pid, result},
        %__MODULE__{sync_task_pid: pid, sync_task_ref: ref} = state
      ) do
    Process.demonitor(ref, [:flush])

    record_event? = state.sync_record_event
    waiters = state.sync_waiters

    next_state =
      state
      |> clear_sync_task()
      |> complete_sync(result, record_event?, waiters)
      |> maybe_start_queued_sync()
      |> maybe_schedule_poll()

    {:noreply, next_state}
  end

  def handle_info(
        {:DOWN, ref, :process, pid, reason},
        %__MODULE__{sync_task_pid: pid, sync_task_ref: ref} = state
      ) do
    record_event? = state.sync_record_event
    waiters = state.sync_waiters

    next_state =
      state
      |> clear_sync_task()
      |> complete_sync({:error, {:sync_task_exit, reason}}, record_event?, waiters)
      |> maybe_start_queued_sync()
      |> maybe_schedule_poll()

    {:noreply, next_state}
  end

  def handle_info({:submit_operation_stage, operation_id, stage, metadata}, %__MODULE__{} = state) do
    {:noreply,
     update_submit_operation(state, operation_id, fn operation ->
       operation
       |> Map.put("status", stage)
       |> Map.put("updated_at", now_iso8601())
       |> maybe_merge_operation_metadata(metadata)
     end)}
  end

  def handle_info(
        {:submit_operation_result, operation_id, {:ok, contribution}},
        %__MODULE__{} = state
      ) do
    next_state =
      state
      |> clear_submit_task(operation_id)
      |> update_submit_operation(operation_id, fn operation ->
        operation
        |> Map.put("status", "completed")
        |> Map.put("updated_at", now_iso8601())
        |> Map.put("completed_at", now_iso8601())
        |> Map.put("contribution_type", contribution_kind(contribution))
        |> Map.put("summary", contribution_summary(contribution))
        |> Map.put("context_count", contribution_context_count(contribution))
        |> Map.put("error", nil)
      end)

    send(self(), {:sync_room_async, true})

    {:noreply,
     record_session_event(next_state, %{
       type: "embedded.chat.completed",
       room_id: state.room_id,
       payload: %{
         "operation_id" => operation_id,
         "summary" => contribution_summary(contribution),
         "contribution_type" => contribution_kind(contribution)
       }
     })}
  end

  def handle_info(
        {:submit_operation_result, operation_id, {:error, reason}},
        %__MODULE__{} = state
      ) do
    next_state =
      state
      |> clear_submit_task(operation_id)
      |> update_submit_operation(operation_id, fn operation ->
        operation
        |> Map.put("status", "failed")
        |> Map.put("updated_at", now_iso8601())
        |> Map.put("completed_at", now_iso8601())
        |> Map.put("error", inspect(reason))
      end)

    {:noreply,
     next_state
     |> put_session_error(reason)
     |> record_session_event(%{
       type: "embedded.chat.failed",
       room_id: state.room_id,
       payload: %{
         "operation_id" => operation_id,
         "reason" => inspect(reason)
       }
     })}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %__MODULE__{} = state) do
    case submit_operation_id_for_ref(state, ref) do
      nil ->
        {:noreply, state}

      operation_id ->
        next_state =
          state
          |> clear_submit_task(operation_id)
          |> update_submit_operation(operation_id, fn operation ->
            operation
            |> Map.put("status", "failed")
            |> Map.put("updated_at", now_iso8601())
            |> Map.put("completed_at", now_iso8601())
            |> Map.put("error", inspect({:submit_task_exit, reason}))
          end)

        {:noreply, next_state}
    end
  end

  @impl true
  def terminate(_reason, %__MODULE__{sync_task_pid: sync_task_pid} = state) do
    if is_pid(sync_task_pid), do: Process.exit(sync_task_pid, :shutdown)
    _state = update_session_connection(state, :stopped, %{})
    :ok
  end

  defp terminal_poll_halted?(%__MODULE__{polling: %{halted_reason: reason}})
       when not is_nil(reason),
       do: true

  defp terminal_poll_halted?(%__MODULE__{}), do: false

  defp handle_poll(%__MODULE__{} = state) do
    if terminal_poll_halted?(state) do
      {:noreply, state}
    else
      {:noreply, request_sync(state, false, [], false)}
    end
  end

  defp current_snapshot(%__MODULE__{} = state) do
    normalized_snapshot =
      state.room_snapshot
      |> normalize_room_snapshot()
      |> Map.delete(:room_id)
      |> Map.delete("room_id")

    snapshot_id =
      Map.get(normalized_snapshot, :id) || Map.get(normalized_snapshot, "id") || state.room_id

    normalized_snapshot
    |> Map.put("id", snapshot_id)
    |> Map.put("participant", state.participant)
    |> Map.put("session_state", SessionState.snapshot(state.session_state))
    |> Map.put("timeline", state.timeline)
    |> Map.put("context_objects", state.context_objects)
    |> Map.put("next_cursor", state.next_cursor)
    |> Map.put("last_sync_at", state.last_sync_at)
    |> Map.put("last_error", state.last_error)
    |> Map.put("operations", current_operations(state))
    |> Map.put("transport", TransportHTTP.diagnostics())
  end

  defp request_sync(%__MODULE__{} = state, record_event?, waiters, force_full?) do
    if sync_inflight?(state) do
      %{
        state
        | sync_queued: true,
          sync_queued_record_event: state.sync_queued_record_event || record_event?,
          sync_queued_force_full: state.sync_queued_force_full || force_full?,
          queued_sync_waiters: state.queued_sync_waiters ++ waiters
      }
    else
      start_sync_task(state, record_event?, waiters, force_full?)
    end
  end

  defp chat_input(attrs, %__MODULE__{} = state) do
    ChatInput.new(%{
      room_id: state.room_id,
      participant_id: state.participant.participant_id,
      participant_role: state.participant.participant_role,
      participant_kind: state.participant.participant_kind,
      text: Map.get(attrs, :text) || Map.get(attrs, "text"),
      local_context: %{
        "timeline_count" => length(state.timeline),
        "context_count" => length(state.context_objects),
        "selected_context_id" =>
          Map.get(attrs, :selected_context_id) || Map.get(attrs, "selected_context_id"),
        "selected_context_object_type" =>
          Map.get(attrs, :selected_context_object_type) ||
            Map.get(attrs, "selected_context_object_type"),
        "selected_relation" =>
          Map.get(attrs, :selected_relation) || Map.get(attrs, "selected_relation") ||
            "contextual"
      }
    })
  end

  defp start_sync_task(%__MODULE__{} = state, record_event?, waiters, force_full?) do
    next_state = cancel_poll_timer(state)
    parent = self()
    sync_state = next_state

    {pid, ref} =
      spawn_monitor(fn ->
        send(parent, {:sync_result, self(), fetch_sync_result(sync_state, force_full?)})
      end)

    %{
      next_state
      | sync_task_pid: pid,
        sync_task_ref: ref,
        sync_waiters: waiters,
        sync_record_event: record_event?,
        sync_force_full: force_full?
    }
  end

  defp maybe_start_queued_sync(%__MODULE__{sync_queued: false} = state), do: state

  defp maybe_start_queued_sync(%__MODULE__{} = state) do
    waiters = state.queued_sync_waiters
    record_event? = state.sync_queued_record_event
    force_full? = state.sync_queued_force_full

    state
    |> Map.put(:sync_queued, false)
    |> Map.put(:sync_queued_record_event, false)
    |> Map.put(:sync_queued_force_full, false)
    |> Map.put(:queued_sync_waiters, [])
    |> start_sync_task(record_event?, waiters, force_full?)
  end

  defp clear_sync_task(%__MODULE__{} = state) do
    %{
      state
      | sync_task_pid: nil,
        sync_task_ref: nil,
        sync_waiters: [],
        sync_record_event: false,
        sync_force_full: false
    }
  end

  defp complete_sync(%__MODULE__{} = state, {:ok, sync_result}, record_event?, waiters) do
    {next_state, changed?} = apply_sync_result(state, sync_result, record_event?)

    if changed? do
      broadcast_snapshot(next_state)
    end

    reply_sync_waiters(waiters, {:ok, current_snapshot(next_state)})
    next_state
  end

  defp complete_sync(%__MODULE__{} = state, {:error, reason}, record_event?, waiters) do
    next_state =
      state
      |> Map.put(:last_error, reason)
      |> put_session_error(reason)
      |> put_polling(
        failure_count: state.polling.failure_count + 1,
        idle_count: 0,
        next_delay_ms:
          Polling.failure_backoff_delay(
            state.polling.interval_ms,
            state.polling.failure_count + 1
          )
      )
      |> maybe_halt_polling(reason)
      |> maybe_record_sync_failure(record_event?)

    broadcast_snapshot(next_state)
    reply_sync_waiters(waiters, {:error, reason})
    next_state
  end

  defp fetch_sync_result(%__MODULE__{} = state, force_full?) do
    _ = force_full?

    with {:ok, room_snapshot} <-
           state.room_api.fetch_room(room_api_sync_opts(state), state.room_id),
         {:ok, %{entries: entries, next_cursor: next_cursor}} <-
           state.room_api.list_events(room_api_sync_opts(state), state.room_id,
             after: state.next_cursor
           ) do
      normalized_snapshot = normalize_room_snapshot(room_snapshot)

      {:ok,
       %{
         room_snapshot: normalized_snapshot,
         entries: entries,
         next_cursor: next_cursor,
         context_objects:
           Map.get(
             normalized_snapshot,
             "context_objects",
             Map.get(normalized_snapshot, :context_objects, [])
           ),
         operations: Map.get(normalized_snapshot, "operations", [])
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_sync_result(%__MODULE__{} = state, sync_result, record_event?) do
    room_snapshot =
      case sync_result.room_snapshot do
        nil ->
          state.room_snapshot

        snapshot ->
          snapshot
          |> normalize_room_snapshot()
          |> Map.put("operations", sync_result.operations || [])
      end

    timeline =
      state.timeline
      |> append_timeline_entries(sync_result.entries)
      |> Enum.take(-@timeline_limit)

    changed? = sync_changed?(state, room_snapshot, timeline, sync_result.context_objects)
    {idle_poll_count, next_poll_delay_ms} = next_success_polling(state, changed?)

    next_state =
      %{
        state
        | room_snapshot: room_snapshot,
          timeline: timeline,
          context_objects: sync_result.context_objects,
          next_cursor: sync_result.next_cursor || state.next_cursor,
          last_sync_at: DateTime.utc_now(),
          last_error: nil
      }
      |> clear_session_error()
      |> put_polling(
        failure_count: 0,
        next_delay_ms: next_poll_delay_ms,
        idle_count: idle_poll_count,
        halted_reason: nil
      )

    next_state =
      if changed? and record_event? do
        record_session_event(next_state, %{
          type: "embedded.sync.updated",
          room_id: state.room_id,
          payload: %{
            "new_entries" => length(sync_result.entries),
            "context_count" => length(sync_result.context_objects)
          }
        })
      else
        next_state
      end

    {next_state, changed?}
  end

  defp normalize_room_snapshot(%{"data" => %{} = snapshot}), do: snapshot
  defp normalize_room_snapshot(%{data: %{} = snapshot}), do: snapshot
  defp normalize_room_snapshot(%{} = snapshot), do: snapshot
  defp normalize_room_snapshot(_other), do: %{}

  defp append_timeline_entries(existing, []), do: existing

  defp append_timeline_entries(existing, entries) do
    seen =
      existing
      |> Enum.map(&timeline_entry_key/1)
      |> MapSet.new()

    {timeline, _seen} =
      Enum.reduce(entries, {existing, seen}, fn entry, {acc, seen_keys} ->
        key = timeline_entry_key(entry)

        cond do
          is_nil(key) ->
            {acc ++ [entry], seen_keys}

          MapSet.member?(seen_keys, key) ->
            {acc, seen_keys}

          true ->
            {acc ++ [entry], MapSet.put(seen_keys, key)}
        end
      end)

    timeline
  end

  defp timeline_entry_key(entry) do
    Map.get(entry, "cursor") || Map.get(entry, "event_id") || Map.get(entry, "entry_id")
  end

  defp reply_sync_waiters([], _reply), do: :ok

  defp reply_sync_waiters(waiters, reply) do
    Enum.each(waiters, &GenServer.reply(&1, reply))
  end

  defp sync_inflight?(%__MODULE__{sync_task_pid: pid, sync_task_ref: ref}) do
    is_pid(pid) and is_reference(ref)
  end

  defp maybe_halt_polling(%__MODULE__{} = state, reason) do
    if room_not_found?(reason) and state.polling.failure_count >= @room_not_found_retry_limit do
      put_polling(state, halted_reason: reason)
    else
      state
    end
  end

  defp room_not_found?(:room_not_found), do: true
  defp room_not_found?(:not_found), do: true
  defp room_not_found?(_reason), do: false

  defp maybe_schedule_poll(%__MODULE__{} = state) do
    cond do
      terminal_poll_halted?(state) -> state
      sync_inflight?(state) -> state
      true -> schedule_poll(state, state.polling.next_delay_ms)
    end
  end

  defp schedule_poll(%__MODULE__{} = state, delay_ms)
       when is_integer(delay_ms) and delay_ms >= 0 do
    next_state = cancel_poll_timer(state)
    token = make_ref()
    timer_ref = Process.send_after(self(), {:poll, token}, delay_ms)
    put_polling(next_state, timer_ref: {timer_ref, token})
  end

  defp cancel_poll_timer(%__MODULE__{polling: %{timer_ref: nil}} = state), do: state

  defp cancel_poll_timer(%__MODULE__{polling: %{timer_ref: timer_ref}} = state) do
    {native_timer_ref, _token} = timer_ref
    Process.cancel_timer(native_timer_ref, async: true, info: false)
    put_polling(state, timer_ref: nil)
  end

  defp clear_poll_timer(%__MODULE__{} = state), do: put_polling(state, timer_ref: nil)

  defp new_polling_state(interval_ms) do
    %{
      timer_ref: nil,
      interval_ms: interval_ms,
      next_delay_ms: interval_ms,
      failure_count: 0,
      idle_count: 0,
      halted_reason: nil
    }
  end

  defp put_polling(%__MODULE__{} = state, attrs) when is_list(attrs) do
    %{state | polling: Map.merge(state.polling, Map.new(attrs))}
  end

  defp sync_changed?(%__MODULE__{} = state, room_snapshot, timeline, context_objects) do
    room_snapshot != state.room_snapshot or
      timeline != state.timeline or
      context_objects != state.context_objects or
      not is_nil(state.last_error)
  end

  defp next_success_polling(%__MODULE__{} = state, true) do
    {0, state.polling.interval_ms}
  end

  defp next_success_polling(%__MODULE__{} = state, false) do
    idle_count = state.polling.idle_count + 1
    {idle_count, Polling.idle_backoff_delay(state.polling.interval_ms, idle_count)}
  end

  defp acceptance_contribution(context_object, attrs, %__MODULE__{} = state) do
    title = value(context_object, "title") || value(context_object, "body") || "Accepted decision"
    context_id = value(context_object, "context_id")

    %{
      "room_id" => state.room_id,
      "participant_id" => state.participant.participant_id,
      "kind" => "decision",
      "payload" => %{
        "summary" =>
          Map.get(attrs, "summary") || Map.get(attrs, :summary) || "Accepted: #{title}",
        "context_objects" => [
          %{
            "object_type" => "decision",
            "title" => title,
            "body" => value(context_object, "body") || title,
            "relations" => [%{"relation" => "derives_from", "target_id" => context_id}]
          }
        ]
      },
      "meta" => %{
        "participant_role" => state.participant.participant_role,
        "participant_kind" => state.participant.participant_kind,
        "authority_level" => "binding",
        "events" => [%{"event_type" => "accept", "context_id" => context_id}],
        "execution" => %{"status" => "completed"},
        "status" => "completed"
      }
    }
  end

  defp participant_from_opts(opts) do
    %{
      participant_id:
        Keyword.get(opts, :participant_id, "human-#{System.unique_integer([:positive])}"),
      participant_role: Keyword.get(opts, :participant_role, "collaborator"),
      participant_kind: Keyword.get(opts, :participant_kind, "human"),
      authority_profile: %{
        decision_authority: Keyword.get(opts, :decision_authority, :binding),
        validation_authority: Keyword.get(opts, :validation_authority, :advisory)
      }
    }
  end

  defp new_session_state(opts, participant) do
    session_opts = [
      workspace_id: Keyword.get(opts, :workspace_id, "workspace-local"),
      user_id: Keyword.get(opts, :user_id, participant.participant_id),
      participant_id: participant.participant_id,
      participant_role: participant.participant_role,
      participant_kind: participant.participant_kind,
      target_id: Keyword.get(opts, :target_id, "embedded-#{participant.participant_id}"),
      capability_id: Keyword.get(opts, :capability_id, "human.chat"),
      workspace_root: Keyword.get(opts, :workspace_root, File.cwd!()),
      room_id: Keyword.fetch!(opts, :room_id)
    ]

    SessionState.new(session_opts)
  end

  defp update_session_connection(%__MODULE__{} = state, status, payload) do
    %{
      state
      | session_state: SessionState.connection_changed(state.session_state, status, payload)
    }
  end

  defp record_session_event(%__MODULE__{} = state, attrs) when is_map(attrs) do
    {event_log, entry} = SessionEventLog.append(state.event_log, attrs)
    next_session_state = SessionState.record_event(state.session_state, entry)

    Enum.each(state.subscribers, &send(&1, {:client_runtime_event, entry}))

    %{state | event_log: event_log, session_state: next_session_state}
  end

  defp put_session_error(%__MODULE__{} = state, reason) do
    %{state | session_state: SessionState.put_error(state.session_state, reason)}
  end

  defp clear_session_error(%__MODULE__{} = state) do
    %{state | session_state: SessionState.clear_error(state.session_state)}
  end

  defp maybe_record_sync_failure(%__MODULE__{} = state, true) do
    record_session_event(state, %{
      type: "embedded.sync.failed",
      room_id: state.room_id,
      payload: %{"reason" => inspect(state.last_error)}
    })
  end

  defp maybe_record_sync_failure(%__MODULE__{} = state, false), do: state

  defp normalize_room_api(nil), do: {HttpRoomApi, []}

  defp normalize_room_api({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_room_api(module) when is_atom(module), do: {module, []}
  defp normalize_room_api(_other), do: {HttpRoomApi, []}

  defp normalize_agent_backend(nil), do: {Mock, []}

  defp normalize_agent_backend({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_agent_backend(module) when is_atom(module), do: {module, []}
  defp normalize_agent_backend(_other), do: {Mock, []}

  defp prepare_chat_contribution(attrs, %__MODULE__{} = state) do
    with {:ok, chat_input} <- chat_input(attrs, state),
         {:ok, intercepted} <-
           Interceptor.extract(chat_input,
             backend: {state.agent_backend, state.agent_backend_opts}
           ) do
      {:ok,
       Interceptor.to_contribution(intercepted, %{
         room_id: state.room_id,
         participant_id: state.participant.participant_id,
         participant_role: state.participant.participant_role,
         participant_kind: state.participant.participant_kind
       })}
    end
  end

  defp start_submit_task(%__MODULE__{} = state, operation_id, attrs) do
    parent = self()
    submit_state = state

    {pid, ref} =
      spawn_monitor(fn -> run_submit_task(parent, operation_id, attrs, submit_state) end)

    %{state | submit_tasks: Map.put(state.submit_tasks, operation_id, %{pid: pid, ref: ref})}
  end

  defp run_submit_task(parent, operation_id, attrs, submit_state) do
    send(parent, {:submit_operation_stage, operation_id, "preparing", %{}})
    result = submit_task_result(parent, operation_id, attrs, submit_state)
    send(parent, {:submit_operation_result, operation_id, result})
  end

  defp submit_task_result(parent, operation_id, attrs, submit_state) do
    with {:ok, contribution} <- prepare_chat_contribution(attrs, submit_state) do
      send_submit_stage(parent, operation_id, contribution)
      submit_prepared_contribution(parent, operation_id, submit_state, contribution)
    end
  end

  defp send_submit_stage(parent, operation_id, contribution) do
    send(
      parent,
      {:submit_operation_stage, operation_id, "sending",
       %{
         "contribution_type" => contribution_kind(contribution),
         "context_count" => contribution_context_count(contribution)
       }}
    )
  end

  defp submit_prepared_contribution(parent, operation_id, submit_state, contribution) do
    case submit_state.room_api.submit_contribution(
           room_api_submit_opts(submit_state, operation_id),
           submit_state.room_id,
           contribution
         ) do
      {:ok, _response} ->
        send(parent, {:submit_operation_stage, operation_id, "server_acknowledged", %{}})
        {:ok, contribution}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp submit_operation_id_for_ref(%__MODULE__{} = state, ref) do
    Enum.find_value(state.submit_tasks, fn {operation_id, task} ->
      if task.ref == ref, do: operation_id, else: nil
    end)
  end

  defp clear_submit_task(%__MODULE__{} = state, operation_id) do
    case Map.pop(state.submit_tasks, operation_id) do
      {%{ref: ref}, tasks} ->
        Process.demonitor(ref, [:flush])
        %{state | submit_tasks: tasks}

      {nil, _tasks} ->
        state
    end
  end

  defp put_submit_operation(%__MODULE__{} = state, operation) do
    operation_id = operation["operation_id"]

    submit_order =
      [operation_id | Enum.reject(state.submit_order, &(&1 == operation_id))]
      |> Enum.take(@operation_history_limit)

    operations =
      state.submit_operations
      |> Map.put(operation_id, operation)
      |> Map.take(submit_order)

    next_state = %{state | submit_operations: operations, submit_order: submit_order}
    broadcast_snapshot(next_state)
    next_state
  end

  defp update_submit_operation(%__MODULE__{} = state, operation_id, fun) do
    case Map.fetch(state.submit_operations, operation_id) do
      {:ok, operation} ->
        put_submit_operation(state, fun.(operation))

      :error ->
        state
    end
  end

  defp current_operations(%__MODULE__{} = state) do
    submit_operations =
      Enum.map(state.submit_order, &Map.get(state.submit_operations, &1))
      |> Enum.reject(&is_nil/1)

    server_operations =
      state.room_snapshot
      |> value("operations")
      |> case do
        operations when is_list(operations) -> operations
        _other -> []
      end

    merge_operations(submit_operations, server_operations)
  end

  defp merge_operations(local_operations, server_operations) do
    (local_operations ++ server_operations)
    |> Enum.reduce({[], MapSet.new()}, &merge_operation/2)
    |> elem(0)
    |> Enum.reverse()
  end

  defp merge_operation(operation, {acc, seen}) do
    operation_id = value(operation, "operation_id")

    if duplicate_operation?(operation_id, seen) do
      {acc, seen}
    else
      {[operation | acc], remember_operation(seen, operation_id)}
    end
  end

  defp duplicate_operation?(operation_id, seen) when is_binary(operation_id),
    do: MapSet.member?(seen, operation_id)

  defp duplicate_operation?(_operation_id, _seen), do: false

  defp remember_operation(seen, operation_id) when is_binary(operation_id),
    do: MapSet.put(seen, operation_id)

  defp remember_operation(seen, _operation_id), do: seen

  defp maybe_push_subscriber_snapshot(pid, %__MODULE__{} = state) do
    if subscriber_snapshot_ready?(state) do
      push_snapshot(pid, current_snapshot(state))
    end
  end

  defp subscriber_snapshot_ready?(%__MODULE__{} = state) do
    not is_nil(state.last_sync_at) or
      not is_nil(state.last_error) or
      map_size(state.room_snapshot) > 0 or
      state.timeline != [] or
      state.context_objects != [] or
      map_size(state.submit_operations) > 0
  end

  defp broadcast_snapshot(%__MODULE__{subscribers: subscribers} = state) do
    snapshot = current_snapshot(state)
    Enum.each(subscribers, &push_snapshot(&1, snapshot))
    state
  end

  defp push_snapshot(pid, snapshot) when is_pid(pid) do
    room_id = Map.get(snapshot, :id) || Map.get(snapshot, "id")

    send(pid, {:room_session_snapshot, room_id, snapshot})
  end

  defp new_submit_operation(operation_id, text) do
    %{
      "operation_id" => operation_id,
      "kind" => "submit_chat",
      "lane" => "room_submit",
      "status" => "accepted",
      "text" => text,
      "chars" => String.length(text),
      "accepted_at" => now_iso8601(),
      "updated_at" => now_iso8601(),
      "completed_at" => nil,
      "error" => nil
    }
  end

  defp maybe_merge_operation_metadata(operation, metadata) when map_size(metadata) == 0,
    do: operation

  defp maybe_merge_operation_metadata(operation, metadata), do: Map.merge(operation, metadata)

  defp room_api_submit_opts(%__MODULE__{} = state, operation_id) do
    state.room_api_opts
    |> Keyword.put(:lane, :room_submit)
    |> Keyword.put(:operation_id, operation_id)
    |> Keyword.put(:request_timeout_ms, 15_000)
    |> Keyword.put(:connect_timeout_ms, 5_000)
  end

  defp room_api_sync_opts(%__MODULE__{} = state) do
    state.room_api_opts
    |> Keyword.put(:lane, :room_sync)
    |> Keyword.put_new(:request_timeout_ms, 10_000)
    |> Keyword.put_new(:connect_timeout_ms, 3_000)
  end

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  defp context_id_matches?(context_object, context_id) do
    value(context_object, "context_id") == context_id
  end

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp contribution_payload(contribution) when is_map(contribution) do
    Map.get(contribution, "payload") || Map.get(contribution, :payload) || %{}
  end

  defp contribution_kind(contribution) do
    Map.get(contribution, "kind") || Map.get(contribution, :kind)
  end

  defp contribution_summary(contribution) do
    payload = contribution_payload(contribution)

    Map.get(payload, "summary") || Map.get(payload, :summary) || Map.get(payload, "text") ||
      Map.get(payload, :text) || Map.get(payload, "title") || Map.get(payload, :title)
  end

  defp contribution_context_objects(contribution) do
    payload = contribution_payload(contribution)
    Map.get(payload, "context_objects") || Map.get(payload, :context_objects) || []
  end

  defp contribution_context_count(contribution) do
    contribution
    |> contribution_context_objects()
    |> length()
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
