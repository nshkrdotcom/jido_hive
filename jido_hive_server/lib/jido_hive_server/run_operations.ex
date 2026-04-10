defmodule JidoHiveServer.RunOperations do
  @moduledoc false

  use GenServer

  alias JidoHiveServer.Collaboration

  defstruct operations: %{}, tasks: %{}

  @type operation :: map()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, %__MODULE__{}, name: name)
      :error -> GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
    end
  end

  @spec start_run(String.t(), keyword()) :: {:ok, operation()} | {:error, term()}
  def start_run(room_id, run_opts \\ []) when is_binary(room_id) and is_list(run_opts) do
    GenServer.call(__MODULE__, {:start_run, room_id, run_opts})
  end

  @spec fetch(String.t(), String.t()) :: {:ok, operation()} | {:error, term()}
  def fetch(room_id, operation_id)
      when is_binary(room_id) and is_binary(operation_id) do
    GenServer.call(__MODULE__, {:fetch, room_id, operation_id})
  end

  @spec list(String.t()) :: {:ok, [operation()]} | {:error, term()}
  def list(room_id) when is_binary(room_id) do
    GenServer.call(__MODULE__, {:list, room_id})
  end

  @impl true
  def init(%__MODULE__{} = state), do: {:ok, state}

  @impl true
  def handle_call({:start_run, room_id, run_opts}, _from, %__MODULE__{} = state) do
    case Collaboration.fetch_room(room_id) do
      {:ok, _snapshot} ->
        operation_id = new_operation_id("room_run")
        accepted_at = now_iso8601()

        operation = %{
          operation_id: operation_id,
          client_operation_id: Keyword.get(run_opts, :client_operation_id),
          room_id: room_id,
          kind: "room_run",
          lane: "room_run",
          status: "accepted",
          phase: "accepted",
          assignment_timeout_ms: Keyword.get(run_opts, :assignment_timeout_ms),
          max_assignments: Keyword.get(run_opts, :max_assignments),
          accepted_at: accepted_at,
          started_at: nil,
          completed_at: nil,
          updated_at: accepted_at,
          result: nil,
          error: nil
        }

        task =
          Task.Supervisor.async_nolink(JidoHiveServer.RunOperationTaskSupervisor, fn ->
            Collaboration.run_room(room_id, run_opts)
          end)

        next_state =
          state
          |> put_operation(operation_id, operation)
          |> put_task(task.ref, operation_id)

        send(self(), {:mark_running, operation_id})

        {:reply, {:ok, operation}, next_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:fetch, room_id, operation_id}, _from, %__MODULE__{} = state) do
    case Map.get(state.operations, operation_id) do
      %{room_id: ^room_id} = operation -> {:reply, {:ok, operation}, state}
      _other -> {:reply, {:error, :operation_not_found}, state}
    end
  end

  def handle_call({:list, room_id}, _from, %__MODULE__{} = state) do
    operations =
      state.operations
      |> Map.values()
      |> Enum.filter(&(&1.room_id == room_id))
      |> Enum.sort_by(&operation_sort_key/1, {:desc, String})

    {:reply, {:ok, operations}, state}
  end

  @impl true
  def handle_info({:mark_running, operation_id}, %__MODULE__{} = state) do
    {:noreply, update_operation(state, operation_id, &mark_running/1)}
  end

  def handle_info({ref, result}, %__MODULE__{} = state) when is_reference(ref) do
    case Map.get(state.tasks, ref) do
      nil ->
        {:noreply, state}

      operation_id ->
        Process.demonitor(ref, [:flush])

        next_state =
          state
          |> drop_task(ref)
          |> update_operation(operation_id, &complete_operation(&1, result))

        {:noreply, next_state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %__MODULE__{} = state) do
    case Map.get(state.tasks, ref) do
      nil ->
        {:noreply, state}

      operation_id ->
        next_state =
          state
          |> drop_task(ref)
          |> update_operation(operation_id, &fail_operation(&1, {:task_exit, reason}))

        {:noreply, next_state}
    end
  end

  defp put_operation(%__MODULE__{} = state, operation_id, operation) do
    %{state | operations: Map.put(state.operations, operation_id, operation)}
  end

  defp put_task(%__MODULE__{} = state, ref, operation_id) do
    %{state | tasks: Map.put(state.tasks, ref, operation_id)}
  end

  defp drop_task(%__MODULE__{} = state, ref) do
    %{state | tasks: Map.delete(state.tasks, ref)}
  end

  defp update_operation(%__MODULE__{} = state, operation_id, fun) do
    case Map.fetch(state.operations, operation_id) do
      {:ok, operation} ->
        %{state | operations: Map.put(state.operations, operation_id, fun.(operation))}

      :error ->
        state
    end
  end

  defp mark_running(operation) do
    operation
    |> Map.put(:status, "running")
    |> Map.put(:phase, "running")
    |> Map.put(:started_at, now_iso8601())
    |> Map.put(:updated_at, now_iso8601())
  end

  defp complete_operation(operation, {:ok, snapshot}) do
    operation
    |> Map.put(:status, "completed")
    |> Map.put(:phase, "completed")
    |> Map.put(:completed_at, now_iso8601())
    |> Map.put(:updated_at, now_iso8601())
    |> Map.put(:result, summarize_snapshot(snapshot))
    |> Map.put(:error, nil)
  end

  defp complete_operation(operation, {:error, reason}) do
    fail_operation(operation, reason)
  end

  defp fail_operation(operation, reason) do
    operation
    |> Map.put(:status, "failed")
    |> Map.put(:phase, "failed")
    |> Map.put(:completed_at, now_iso8601())
    |> Map.put(:updated_at, now_iso8601())
    |> Map.put(:result, nil)
    |> Map.put(:error, inspect(reason))
  end

  defp summarize_snapshot(snapshot) when is_map(snapshot) do
    %{
      status: Map.get(snapshot, :status) || Map.get(snapshot, "status"),
      dispatch_state: Map.get(snapshot, :dispatch_state) || Map.get(snapshot, "dispatch_state"),
      participant_count:
        length(Map.get(snapshot, :participants) || Map.get(snapshot, "participants", []))
    }
  end

  defp new_operation_id(prefix) do
    suffix =
      6
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    "#{prefix}-#{suffix}"
  end

  defp operation_sort_key(operation) do
    operation.updated_at || operation.accepted_at || operation.operation_id
  end

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end
end
