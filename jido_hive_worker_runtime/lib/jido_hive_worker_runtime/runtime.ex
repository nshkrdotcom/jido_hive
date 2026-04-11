defmodule JidoHiveWorkerRuntime.Runtime do
  @moduledoc false

  use GenServer

  alias JidoHiveWorkerRuntime.Boundary.ProtocolCodec
  alias JidoHiveWorkerRuntime.{EventLog, Runtime.State}

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

  @spec record_event(pid() | atom(), map()) :: :ok
  def record_event(server \\ __MODULE__, attrs) when is_map(attrs) do
    GenServer.call(server, {:record_event, attrs})
  end

  @spec record_contribution_published(pid() | atom(), map(), map()) :: :ok
  def record_contribution_published(server \\ __MODULE__, assignment, contribution)
      when is_map(assignment) and is_map(contribution) do
    GenServer.call(server, {:contribution_published, assignment, contribution})
  end

  @spec assignment_failed(pid() | atom(), map(), term()) :: :ok
  def assignment_failed(server \\ __MODULE__, assignment, reason) when is_map(assignment) do
    GenServer.call(server, {:assignment_failed, assignment, reason})
  end

  @spec run_assignment(pid() | atom(), map()) :: {:ok, map()} | {:error, term()}
  def run_assignment(server \\ __MODULE__, assignment) when is_map(assignment) do
    with {:ok, normalized_assignment} <- ProtocolCodec.normalize_assignment_start(assignment),
         {module, executor_opts} <- GenServer.call(server, :executor),
         :ok <- GenServer.call(server, {:assignment_received, normalized_assignment}),
         :ok <- GenServer.call(server, {:assignment_started, normalized_assignment}) do
      case module.run(normalized_assignment, executor_opts) do
        {:ok, result} ->
          normalized_contribution =
            ProtocolCodec.normalize_contribution(result, normalized_assignment)

          :ok =
            GenServer.call(
              server,
              {:assignment_completed, normalized_assignment, normalized_contribution}
            )

          {:ok, normalized_contribution}

        {:error, reason} = error ->
          :ok = GenServer.call(server, {:assignment_failed, normalized_assignment, reason})
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

  def handle_call({:record_event, attrs}, _from, %__MODULE__{} = state) do
    {:reply, :ok, append_event(state, attrs)}
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

  def handle_call({:assignment_received, assignment}, _from, %__MODULE__{} = state) do
    next_state =
      state
      |> Map.update!(:snapshot, &State.assignment_received(&1, assignment))
      |> append_event(%{
        type: "client.assignment.received",
        room_id: assignment["room_id"],
        assignment_id: assignment["assignment_id"],
        payload: assignment_payload(assignment)
      })

    {:reply, :ok, next_state}
  end

  def handle_call({:assignment_started, assignment}, _from, %__MODULE__{} = state) do
    next_state =
      state
      |> Map.update!(:snapshot, &State.assignment_started(&1, assignment))
      |> append_event(%{
        type: "client.assignment.started",
        room_id: assignment["room_id"],
        assignment_id: assignment["assignment_id"],
        payload: assignment_payload(assignment)
      })

    {:reply, :ok, next_state}
  end

  def handle_call({:assignment_completed, assignment, contribution}, _from, %__MODULE__{} = state) do
    next_state =
      state
      |> Map.update!(:snapshot, &State.assignment_finished(&1, assignment, contribution))
      |> append_event(%{
        type: "client.assignment.completed",
        room_id: assignment["room_id"],
        assignment_id: assignment["assignment_id"],
        payload: %{
          "status" => contribution["status"],
          "summary" => contribution["summary"],
          "contribution_type" => contribution["contribution_type"]
        }
      })

    {:reply, :ok, next_state}
  end

  def handle_call({:assignment_failed, assignment, reason}, _from, %__MODULE__{} = state) do
    next_state =
      state
      |> Map.update!(:snapshot, &State.assignment_failed(&1, assignment, reason))
      |> append_event(%{
        type: "client.assignment.failed",
        room_id: assignment["room_id"],
        assignment_id: assignment["assignment_id"],
        payload: %{"reason" => inspect(reason)}
      })

    {:reply, :ok, next_state}
  end

  def handle_call(
        {:contribution_published, assignment, contribution},
        _from,
        %__MODULE__{} = state
      ) do
    next_state =
      append_event(state, %{
        type: "client.contribution.published",
        room_id: assignment["room_id"],
        assignment_id: assignment["assignment_id"],
        payload: %{
          "status" => contribution["status"],
          "contribution_type" => contribution["contribution_type"]
        }
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

  defp assignment_payload(assignment) do
    %{
      "participant_id" => assignment["participant_id"],
      "participant_role" => assignment["participant_role"],
      "target_id" => assignment["target_id"],
      "phase" => assignment["phase"]
    }
  end

  defp normalize_executor({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_executor(module) when is_atom(module), do: {module, []}

  defp normalize_executor(_other),
    do: {JidoHiveWorkerRuntime.Executor.Session, [provider: :codex]}

  defp normalize_payload(payload) when is_map(payload), do: payload
  defp normalize_payload(_other), do: %{}
end
