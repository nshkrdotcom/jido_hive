defmodule JidoHiveClient.Runtime do
  @moduledoc false

  use GenServer

  alias JidoHiveClient.Boundary.ProtocolCodec
  alias JidoHiveClient.{EventLog, Runtime.State}

  defstruct snapshot: nil, event_log: nil, executor: nil, subscribers: %{}

  @type server_state :: %__MODULE__{
          snapshot: State.t(),
          event_log: EventLog.t(),
          executor: {module(), keyword()},
          subscribers: %{optional(pid()) => reference()}
        }

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

  @spec configure(pid() | atom(), keyword()) :: :ok
  def configure(server \\ __MODULE__, opts) when is_list(opts) do
    GenServer.call(server, {:configure, opts})
  end

  @spec current_state(pid() | atom()) :: map()
  def current_state(server \\ __MODULE__), do: snapshot(server)

  @spec snapshot(pid() | atom()) :: map()
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  end

  @spec recent_events(pid() | atom(), keyword()) :: [EventLog.event()]
  def recent_events(server \\ __MODULE__, opts \\ []) do
    GenServer.call(server, {:recent_events, opts})
  end

  @spec subscribe(pid() | atom()) :: :ok
  def subscribe(server \\ __MODULE__) do
    GenServer.call(server, {:subscribe, self()})
  end

  @spec connect(pid() | atom(), map()) :: :ok
  def connect(server \\ __MODULE__, attrs \\ %{}) do
    update_connection(server, :ready, attrs)
  end

  @spec disconnect(pid() | atom()) :: :ok
  def disconnect(server \\ __MODULE__) do
    update_connection(server, :stopped, %{})
  end

  @spec update_connection(pid() | atom(), atom(), map()) :: :ok
  def update_connection(server \\ __MODULE__, status, payload \\ %{}) when is_atom(status) do
    GenServer.call(server, {:connection_changed, status, payload})
  end

  @spec record_result_published(pid() | atom(), map(), map()) :: :ok
  def record_result_published(server \\ __MODULE__, job, result)
      when is_map(job) and is_map(result) do
    GenServer.call(server, {:result_published, job, result})
  end

  @spec run_job(pid() | atom(), map()) :: {:ok, map()} | {:error, term()}
  def run_job(server \\ __MODULE__, job) when is_map(job) do
    with {:ok, normalized_job} <- ProtocolCodec.normalize_job_start(job),
         {module, executor_opts} <- GenServer.call(server, :executor),
         :ok <- GenServer.call(server, {:job_received, normalized_job}),
         :ok <- GenServer.call(server, {:job_started, normalized_job}) do
      case module.run(normalized_job, executor_opts) do
        {:ok, result} ->
          normalized_result = ProtocolCodec.normalize_job_result(result, normalized_job)
          :ok = GenServer.call(server, {:job_completed, normalized_job, normalized_result})
          {:ok, normalized_result}

        {:error, reason} = error ->
          :ok = GenServer.call(server, {:job_failed, normalized_job, reason})
          error
      end
    end
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      snapshot: State.new(opts),
      event_log: EventLog.new(limit: Keyword.get(opts, :event_limit, 200)),
      executor: normalize_executor(Keyword.get(opts, :executor)),
      subscribers: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:configure, opts}, _from, %__MODULE__{} = state) do
    next_state = %{
      state
      | snapshot: State.new(opts),
        executor: normalize_executor(opts[:executor])
    }

    {:reply, :ok, next_state}
  end

  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply, State.snapshot(state.snapshot), state}
  end

  def handle_call({:recent_events, opts}, _from, %__MODULE__{} = state) do
    {:reply, EventLog.list(state.event_log, opts), state}
  end

  def handle_call({:subscribe, pid}, _from, %__MODULE__{} = state) when is_pid(pid) do
    ref = Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: Map.put(state.subscribers, pid, ref)}}
  end

  def handle_call(:executor, _from, %__MODULE__{} = state) do
    {:reply, state.executor, state}
  end

  def handle_call({:connection_changed, status, payload}, _from, %__MODULE__{} = state) do
    next_state =
      state
      |> Map.update!(:snapshot, &State.connection_changed(&1, status))
      |> append_event(%{
        type: "client.connection.changed",
        payload: Map.put(normalize_payload(payload), "status", Atom.to_string(status))
      })

    {:reply, :ok, next_state}
  end

  def handle_call({:job_received, job}, _from, %__MODULE__{} = state) do
    next_state =
      state
      |> Map.update!(:snapshot, &State.job_received(&1, job))
      |> append_event(%{
        type: "client.job.received",
        room_id: job["room_id"],
        job_id: job["job_id"],
        payload: job_payload(job)
      })

    {:reply, :ok, next_state}
  end

  def handle_call({:job_started, job}, _from, %__MODULE__{} = state) do
    next_state =
      state
      |> Map.update!(:snapshot, &State.job_started(&1, job))
      |> append_event(%{
        type: "client.job.started",
        room_id: job["room_id"],
        job_id: job["job_id"],
        payload: job_payload(job)
      })

    {:reply, :ok, next_state}
  end

  def handle_call({:job_completed, job, result}, _from, %__MODULE__{} = state) do
    next_state =
      state
      |> Map.update!(:snapshot, &State.job_finished(&1, job, result))
      |> append_event(%{
        type: "client.job.completed",
        room_id: job["room_id"],
        job_id: job["job_id"],
        payload: %{"status" => result["status"], "summary" => result["summary"]}
      })

    {:reply, :ok, next_state}
  end

  def handle_call({:job_failed, job, reason}, _from, %__MODULE__{} = state) do
    next_state =
      state
      |> Map.update!(:snapshot, &State.job_failed(&1, job, reason))
      |> append_event(%{
        type: "client.job.failed",
        room_id: job["room_id"],
        job_id: job["job_id"],
        payload: %{"reason" => inspect(reason)}
      })

    {:reply, :ok, next_state}
  end

  def handle_call({:result_published, job, result}, _from, %__MODULE__{} = state) do
    next_state =
      append_event(state, %{
        type: "client.result.published",
        room_id: job["room_id"],
        job_id: job["job_id"],
        payload: %{"status" => result["status"]}
      })

    {:reply, :ok, next_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, %__MODULE__{} = state) do
    subscribers =
      state.subscribers
      |> Enum.reject(fn {subscriber, monitor_ref} -> subscriber == pid or monitor_ref == ref end)
      |> Map.new()

    {:noreply, %{state | subscribers: subscribers}}
  end

  defp append_event(%__MODULE__{} = state, attrs) do
    {event_log, entry} = EventLog.append(state.event_log, attrs)

    Enum.each(Map.keys(state.subscribers), fn subscriber ->
      send(subscriber, {:client_runtime_event, entry})
    end)

    %{state | event_log: event_log}
  end

  defp job_payload(job) do
    %{
      "participant_id" => job["participant_id"],
      "participant_role" => job["participant_role"],
      "target_id" => job["target_id"],
      "phase" => get_in(job, ["collaboration_envelope", "turn", "phase"])
    }
  end

  defp normalize_executor({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_executor(module) when is_atom(module), do: {module, []}
  defp normalize_executor(_other), do: {JidoHiveClient.Executor.Session, [provider: :codex]}

  defp normalize_payload(payload) when is_map(payload), do: payload
  defp normalize_payload(_other), do: %{}
end
