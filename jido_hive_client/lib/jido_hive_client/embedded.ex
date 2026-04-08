defmodule JidoHiveClient.Embedded do
  @moduledoc false

  use GenServer

  alias JidoHiveClient.AgentBackends.Mock
  alias JidoHiveClient.Boundary.RoomApi.Http, as: HttpRoomApi
  alias JidoHiveClient.{ChatInput, Interceptor, Runtime}

  @default_poll_interval_ms 1_000
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
    poll_interval_ms: @default_poll_interval_ms
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
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)
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

  def handle_call(:refresh, _from, %__MODULE__{} = state) do
    case sync_room(state, record_event?: true) do
      {:ok, next_state, _changed?} -> {:reply, {:ok, current_snapshot(next_state)}, next_state}
      {:error, reason, next_state} -> {:reply, {:error, reason}, next_state}
    end
  end

  def handle_call({:submit_chat, attrs}, _from, %__MODULE__{} = state) do
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
           }),
         {:ok, next_state, _changed?} <- sync_room(state, record_event?: true) do
      {:reply, {:ok, contribution}, next_state}
    else
      {:error, reason} ->
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
               }),
             {:ok, next_state, _changed?} <- sync_room(state, record_event?: true) do
          {:reply, {:ok, contribution}, next_state}
        else
          {:error, reason} -> {:reply, {:error, reason}, %{state | last_error: reason}}
        end
    end
  end

  @impl true
  def handle_info(:poll, %__MODULE__{} = state) do
    next_state =
      case sync_room(state, record_event?: false) do
        {:ok, synced, _changed?} -> synced
        {:error, _reason, failed_state} -> failed_state
      end

    Process.send_after(self(), :poll, next_state.poll_interval_ms)
    {:noreply, next_state}
  end

  def handle_info({:client_runtime_event, event}, %__MODULE__{} = state) do
    Enum.each(state.subscribers, &send(&1, {:client_runtime_event, event}))
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %__MODULE__{runtime: runtime, owned_runtime?: owned_runtime?}) do
    _ = Runtime.disconnect(runtime)
    if owned_runtime? and is_pid(runtime), do: GenServer.stop(runtime)
    :ok
  end

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

  defp sync_room(%__MODULE__{} = state, opts) do
    with {:ok, %{entries: entries, next_cursor: next_cursor}} <-
           state.room_api.fetch_timeline(state.room_api_opts, state.room_id,
             after: state.next_cursor
           ),
         {:ok, context_objects} <-
           state.room_api.fetch_context_objects(state.room_api_opts, state.room_id) do
      timeline = (state.timeline ++ entries) |> Enum.take(-@timeline_limit)
      changed? = entries != [] or context_objects != state.context_objects

      next_state = %{
        state
        | timeline: timeline,
          context_objects: context_objects,
          next_cursor: next_cursor || state.next_cursor,
          last_sync_at: DateTime.utc_now(),
          last_error: nil
      }

      if changed? and Keyword.get(opts, :record_event?, false) do
        :ok =
          Runtime.record_event(state.runtime, %{
            type: "embedded.sync.updated",
            room_id: state.room_id,
            payload: %{
              "new_entries" => length(entries),
              "context_count" => length(context_objects)
            }
          })
      end

      {:ok, next_state, changed?}
    else
      {:error, reason} ->
        if Keyword.get(opts, :record_event?, false) do
          :ok =
            Runtime.record_event(state.runtime, %{
              type: "embedded.sync.failed",
              room_id: state.room_id,
              payload: %{"reason" => inspect(reason)}
            })
        end

        {:error, reason, %{state | last_error: reason}}
    end
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
