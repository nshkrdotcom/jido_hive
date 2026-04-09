defmodule JidoHiveClient.Embedded do
  @moduledoc false

  use GenServer

  alias JidoHiveClient.AgentBackends.Mock
  alias JidoHiveClient.Boundary.RoomApi.Http, as: HttpRoomApi
  alias JidoHiveClient.{ChatInput, DebugTrace, Interceptor, Runtime}

  @default_poll_interval_ms 1_000
  @max_poll_backoff_ms 10_000
  @room_not_found_retry_limit 3
  @timeline_limit 200

  @type snapshot :: %{
          room_id: String.t(),
          participant: map(),
          runtime: map(),
          timeline: [map()],
          context_objects: [map()],
          next_cursor: String.t() | nil,
          last_sync_at: DateTime.t() | nil,
          last_error: term()
        }

  defstruct [
    :runtime,
    :owned_runtime?,
    :room_api,
    :room_api_opts,
    :agent_backend,
    :agent_backend_opts,
    :room_id,
    :participant,
    :last_sync_at,
    :last_error,
    subscribers: MapSet.new(),
    timeline: [],
    context_objects: [],
    next_cursor: nil,
    poll_interval_ms: @default_poll_interval_ms,
    next_poll_delay_ms: @default_poll_interval_ms,
    poll_failure_count: 0,
    polling_halted_reason: nil,
    sync_task_pid: nil,
    sync_task_ref: nil,
    sync_waiters: [],
    sync_record_event: false,
    sync_queued: false,
    sync_queued_record_event: false,
    queued_sync_waiters: []
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
    {runtime, owned_runtime?} = ensure_runtime(opts, participant)
    {room_api, room_api_opts} = normalize_room_api(Keyword.get(opts, :room_api))

    {agent_backend, agent_backend_opts} =
      normalize_agent_backend(Keyword.get(opts, :agent_backend))

    state = %__MODULE__{
      runtime: runtime,
      owned_runtime?: owned_runtime?,
      room_api: room_api,
      room_api_opts:
        [base_url: Keyword.get(opts, :api_base_url)]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Keyword.merge(room_api_opts),
      agent_backend: agent_backend,
      agent_backend_opts: agent_backend_opts,
      room_id: Keyword.fetch!(opts, :room_id),
      participant: participant,
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms),
      next_poll_delay_ms: Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)
    }

    :ok = Runtime.connect(runtime, %{"mode" => "embedded", "room_id" => state.room_id})
    :ok = Runtime.subscribe(runtime)

    :ok =
      Runtime.record_event(runtime, %{
        type: "embedded.started",
        room_id: state.room_id,
        payload: participant
      })

    Process.send_after(self(), :poll, 0)
    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply, current_snapshot(state), state}
  end

  def handle_call(:subscribe, {pid, _tag}, %__MODULE__{} = state) do
    next_state = %{state | subscribers: MapSet.put(state.subscribers, pid)}
    {:reply, :ok, next_state}
  end

  def handle_call(:refresh, from, %__MODULE__{} = state) do
    {:noreply, request_sync(state, true, [from])}
  end

  def handle_call({:submit_chat, attrs}, _from, %__MODULE__{} = state) do
    DebugTrace.emit(:info, "room_session.submit_chat.started", %{
      room_id: state.room_id,
      participant_id: state.participant.participant_id,
      chars: attrs |> Map.get(:text, Map.get(attrs, "text", "")) |> to_string() |> String.length()
    })

    with {:ok, chat_input} <- chat_input(attrs, state),
         {:ok, intercepted} <-
           Interceptor.extract(chat_input,
             backend: {state.agent_backend, state.agent_backend_opts}
           ),
         contribution <-
           Interceptor.to_contribution(intercepted, %{
             room_id: state.room_id,
             participant_id: state.participant.participant_id,
             participant_role: state.participant.participant_role,
             participant_kind: state.participant.participant_kind
           }),
         {:ok, _response} <-
           state.room_api.submit_contribution(state.room_api_opts, state.room_id, contribution),
         :ok <-
           Runtime.record_event(state.runtime, %{
             type: "embedded.chat.submitted",
             room_id: state.room_id,
             payload: %{
               "summary" => contribution["summary"],
               "context_count" => length(contribution["context_objects"] || [])
             }
           }) do
      DebugTrace.emit(:info, "room_session.submit_chat.completed", %{
        room_id: state.room_id,
        participant_id: state.participant.participant_id,
        contribution_type: contribution["contribution_type"],
        context_count: length(contribution["context_objects"] || [])
      })

      send(self(), {:sync_room_async, true})
      {:reply, {:ok, contribution}, %{state | last_error: nil}}
    else
      {:error, reason} ->
        DebugTrace.emit(:error, "room_session.submit_chat.failed", %{
          room_id: state.room_id,
          participant_id: state.participant.participant_id,
          reason: inspect(reason)
        })

        :ok =
          Runtime.record_event(state.runtime, %{
            type: "embedded.chat.failed",
            room_id: state.room_id,
            payload: %{"reason" => inspect(reason)}
          })

        {:reply, {:error, reason}, %{state | last_error: reason}}
    end
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

        with {:ok, _response} <-
               state.room_api.submit_contribution(
                 state.room_api_opts,
                 state.room_id,
                 contribution
               ),
             :ok <-
               Runtime.record_event(state.runtime, %{
                 type: "embedded.context.accepted",
                 room_id: state.room_id,
                 payload: %{"context_id" => context_id}
               }) do
          DebugTrace.emit(:info, "room_session.accept_context.completed", %{
            room_id: state.room_id,
            participant_id: state.participant.participant_id,
            context_id: context_id
          })

          send(self(), {:sync_room_async, true})
          {:reply, {:ok, contribution}, %{state | last_error: nil}}
        else
          {:error, reason} ->
            DebugTrace.emit(:error, "room_session.accept_context.failed", %{
              room_id: state.room_id,
              participant_id: state.participant.participant_id,
              context_id: context_id,
              reason: inspect(reason)
            })

            {:reply, {:error, reason}, %{state | last_error: reason}}
        end
    end
  end

  @impl true
  def handle_info({:sync_room_async, record_event?}, %__MODULE__{} = state) do
    {:noreply, request_sync(state, record_event?)}
  end

  def handle_info(:poll, %__MODULE__{} = state) do
    if terminal_poll_halted?(state) do
      {:noreply, state}
    else
      next_state = request_sync(state, false)

      Process.send_after(self(), :poll, state.next_poll_delay_ms)
      {:noreply, next_state}
    end
  end

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

    {:noreply, next_state}
  end

  def handle_info({:client_runtime_event, event}, %__MODULE__{} = state) do
    Enum.each(state.subscribers, &send(&1, {:client_runtime_event, event}))
    {:noreply, state}
  end

  @impl true
  def terminate(
        _reason,
        %__MODULE__{
          runtime: runtime,
          owned_runtime?: owned_runtime?,
          sync_task_pid: sync_task_pid
        }
      ) do
    if is_pid(sync_task_pid), do: Process.exit(sync_task_pid, :shutdown)
    _ = Runtime.disconnect(runtime)
    if owned_runtime? and is_pid(runtime), do: GenServer.stop(runtime)
    :ok
  end

  defp terminal_poll_halted?(%__MODULE__{polling_halted_reason: reason}) when not is_nil(reason),
    do: true

  defp terminal_poll_halted?(%__MODULE__{}), do: false

  defp current_snapshot(%__MODULE__{} = state) do
    %{
      room_id: state.room_id,
      participant: state.participant,
      runtime: Runtime.snapshot(state.runtime),
      timeline: state.timeline,
      context_objects: state.context_objects,
      next_cursor: state.next_cursor,
      last_sync_at: state.last_sync_at,
      last_error: state.last_error
    }
  end

  defp chat_input(attrs, %__MODULE__{} = state) do
    ChatInput.new(%{
      room_id: state.room_id,
      participant_id: state.participant.participant_id,
      participant_role: state.participant.participant_role,
      participant_kind: state.participant.participant_kind,
      authority_level:
        Map.get(attrs, :authority_level) || Map.get(attrs, "authority_level") || "advisory",
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

  defp request_sync(%__MODULE__{} = state, record_event?, waiters \\ []) do
    if sync_inflight?(state) do
      %{
        state
        | sync_queued: true,
          sync_queued_record_event: state.sync_queued_record_event || record_event?,
          queued_sync_waiters: state.queued_sync_waiters ++ waiters
      }
    else
      start_sync_task(state, record_event?, waiters)
    end
  end

  defp start_sync_task(%__MODULE__{} = state, record_event?, waiters) do
    parent = self()
    sync_state = state

    {pid, ref} =
      spawn_monitor(fn ->
        send(parent, {:sync_result, self(), fetch_sync_result(sync_state)})
      end)

    %{
      state
      | sync_task_pid: pid,
        sync_task_ref: ref,
        sync_waiters: waiters,
        sync_record_event: record_event?
    }
  end

  defp maybe_start_queued_sync(%__MODULE__{sync_queued: false} = state), do: state

  defp maybe_start_queued_sync(%__MODULE__{} = state) do
    waiters = state.queued_sync_waiters
    record_event? = state.sync_queued_record_event

    state
    |> Map.put(:sync_queued, false)
    |> Map.put(:sync_queued_record_event, false)
    |> Map.put(:queued_sync_waiters, [])
    |> start_sync_task(record_event?, waiters)
  end

  defp clear_sync_task(%__MODULE__{} = state) do
    %{
      state
      | sync_task_pid: nil,
        sync_task_ref: nil,
        sync_waiters: [],
        sync_record_event: false
    }
  end

  defp complete_sync(%__MODULE__{} = state, {:ok, sync_result}, record_event?, waiters) do
    {next_state, _changed?} = apply_sync_result(state, sync_result, record_event?)
    maybe_resume_polling(state, next_state)
    reply_sync_waiters(waiters, {:ok, current_snapshot(next_state)})
    next_state
  end

  defp complete_sync(%__MODULE__{} = state, {:error, reason}, record_event?, waiters) do
    if record_event? do
      :ok =
        Runtime.record_event(state.runtime, %{
          type: "embedded.sync.failed",
          room_id: state.room_id,
          payload: %{"reason" => inspect(reason)}
        })
    end

    next_state =
      state
      |> Map.put(:last_error, reason)
      |> Map.put(:poll_failure_count, state.poll_failure_count + 1)
      |> Map.put(
        :next_poll_delay_ms,
        backoff_delay(state.poll_interval_ms, state.poll_failure_count + 1)
      )
      |> maybe_halt_polling(reason)

    reply_sync_waiters(waiters, {:error, reason})
    next_state
  end

  defp fetch_sync_result(%__MODULE__{} = state) do
    with {:ok, %{entries: entries, next_cursor: next_cursor}} <-
           state.room_api.fetch_timeline(state.room_api_opts, state.room_id,
             after: state.next_cursor
           ),
         {:ok, context_objects} <-
           state.room_api.fetch_context_objects(state.room_api_opts, state.room_id) do
      {:ok,
       %{
         entries: entries,
         next_cursor: next_cursor,
         context_objects: context_objects
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_sync_result(%__MODULE__{} = state, sync_result, record_event?) do
    timeline =
      state.timeline
      |> append_timeline_entries(sync_result.entries)
      |> Enum.take(-@timeline_limit)

    changed? = timeline != state.timeline or sync_result.context_objects != state.context_objects

    next_state = %{
      state
      | timeline: timeline,
        context_objects: sync_result.context_objects,
        next_cursor: sync_result.next_cursor || state.next_cursor,
        last_sync_at: DateTime.utc_now(),
        last_error: nil,
        poll_failure_count: 0,
        next_poll_delay_ms: state.poll_interval_ms,
        polling_halted_reason: nil
    }

    if changed? and record_event? do
      :ok =
        Runtime.record_event(state.runtime, %{
          type: "embedded.sync.updated",
          room_id: state.room_id,
          payload: %{
            "new_entries" => length(sync_result.entries),
            "context_count" => length(sync_result.context_objects)
          }
        })
    end

    {next_state, changed?}
  end

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
    if room_not_found?(reason) and state.poll_failure_count >= @room_not_found_retry_limit do
      %{state | polling_halted_reason: reason}
    else
      state
    end
  end

  defp maybe_resume_polling(%__MODULE__{polling_halted_reason: nil}, _next_state), do: :ok

  defp maybe_resume_polling(%__MODULE__{}, %__MODULE__{} = next_state) do
    Process.send_after(self(), :poll, next_state.next_poll_delay_ms)
    :ok
  end

  defp room_not_found?(:room_not_found), do: true
  defp room_not_found?(:not_found), do: true
  defp room_not_found?(_reason), do: false

  defp backoff_delay(base_interval_ms, failures) do
    multiplier = Integer.pow(2, min(failures - 1, 4))
    min(base_interval_ms * multiplier, @max_poll_backoff_ms)
  end

  defp acceptance_contribution(context_object, attrs, %__MODULE__{} = state) do
    title = value(context_object, "title") || value(context_object, "body") || "Accepted decision"
    context_id = value(context_object, "context_id")

    %{
      "room_id" => state.room_id,
      "participant_id" => state.participant.participant_id,
      "participant_role" => state.participant.participant_role,
      "participant_kind" => state.participant.participant_kind,
      "contribution_type" => "decision",
      "authority_level" => "binding",
      "summary" => Map.get(attrs, "summary") || Map.get(attrs, :summary) || "Accepted: #{title}",
      "context_objects" => [
        %{
          "object_type" => "decision",
          "title" => title,
          "body" => value(context_object, "body") || title,
          "relations" => [%{"relation" => "derives_from", "target_id" => context_id}]
        }
      ],
      "events" => [%{"event_type" => "accept", "context_id" => context_id}],
      "execution" => %{"status" => "completed"},
      "status" => "completed"
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

  defp ensure_runtime(opts, participant) do
    runtime_opts = [
      workspace_id: Keyword.get(opts, :workspace_id, "workspace-local"),
      user_id: Keyword.get(opts, :user_id, participant.participant_id),
      participant_id: participant.participant_id,
      participant_role: participant.participant_role,
      target_id: Keyword.get(opts, :target_id, "embedded-#{participant.participant_id}"),
      capability_id: Keyword.get(opts, :capability_id, "human.chat"),
      workspace_root: Keyword.get(opts, :workspace_root, File.cwd!()),
      executor:
        Keyword.get(opts, :executor, {JidoHiveClient.Executor.Scripted, [provider: :codex]}),
      runtime_id: :embedded
    ]

    case Keyword.get(opts, :runtime) do
      nil ->
        {:ok, runtime} = Runtime.start_link(runtime_opts)
        {runtime, true}

      runtime ->
        :ok = Runtime.configure(runtime, runtime_opts)
        {runtime, false}
    end
  end

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

  defp context_id_matches?(context_object, context_id) do
    value(context_object, "context_id") == context_id
  end

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
