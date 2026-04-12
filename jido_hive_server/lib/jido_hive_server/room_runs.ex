defmodule JidoHiveServer.RoomRuns do
  @moduledoc false

  use GenServer

  alias JidoHiveServer.Collaboration
  alias JidoHiveServer.Collaboration.RoomServer
  alias JidoHiveServer.Persistence

  @poll_interval_ms 100

  defstruct tasks: %{}, refs: %{}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, Keyword.take(opts, [:name]))
  end

  def create(room_id, attrs) when is_binary(room_id) and is_map(attrs) do
    GenServer.call(__MODULE__, {:create, room_id, attrs}, :infinity)
  end

  def fetch(room_id, run_id) when is_binary(room_id) and is_binary(run_id) do
    Persistence.fetch_room_run(room_id, run_id)
  end

  def cancel(room_id, run_id) when is_binary(room_id) and is_binary(run_id) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:cancel, room_id, run_id})
    else
      {:error, :room_run_not_found}
    end
  end

  def cancel_active_for_room(room_id) when is_binary(room_id) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:cancel_active_for_room, room_id})
    else
      :ok
    end
  end

  @impl true
  def init(%__MODULE__{} = state), do: {:ok, state}

  @impl true
  def handle_call({:create, room_id, attrs}, _from, state) do
    with {:ok, baseline_snapshot} <- Collaboration.fetch_room_snapshot(room_id),
         {:ok, params} <- normalize_run_attrs(attrs),
         {:ok, run} <- Persistence.create_room_run(initial_run_attrs(room_id, params)),
         task <- start_run_task(run, params, baseline_snapshot) do
      next_state =
        state
        |> put_task(run.id, task)
        |> put_ref(task.ref, run.id)

      {:reply, {:ok, run}, next_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:cancel, room_id, run_id}, _from, state) do
    case Persistence.fetch_room_run(room_id, run_id) do
      {:ok, _run} ->
        stop_task(state.tasks[run_id])
        {:ok, updated} = Persistence.update_room_run(run_id, %{status: "cancelled"})
        {:reply, {:ok, updated}, drop_task(state, run_id)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:cancel_active_for_room, room_id}, _from, state) do
    {:ok, runs} = Persistence.list_active_room_runs(room_id)

    next_state =
      Enum.reduce(runs, state, fn run, acc ->
        stop_task(acc.tasks[run.id])
        _ = Persistence.update_room_run(run.id, %{status: "cancelled"})
        drop_task(acc, run.id)
      end)

    {:reply, :ok, next_state}
  end

  @impl true
  def handle_info({ref, {:ok, run_id, final_attrs}}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    _ = Persistence.update_room_run(run_id, final_attrs)
    {:noreply, drop_task_by_ref(state, ref)}
  end

  def handle_info({ref, {:error, run_id, reason}}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    _ =
      Persistence.update_room_run(run_id, %{
        status: "failed",
        error: %{reason: inspect(reason)}
      })

    {:noreply, drop_task_by_ref(state, ref)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.get(state.refs, ref) do
      nil ->
        {:noreply, state}

      run_id ->
        _ =
          Persistence.update_room_run(run_id, %{
            status: "failed",
            error: %{reason: inspect(reason)}
          })

        {:noreply, drop_task_by_ref(state, ref)}
    end
  end

  defp start_run_task(run, params, baseline_snapshot) do
    Task.Supervisor.async_nolink(JidoHiveServer.RoomRunTaskSupervisor, fn ->
      execute_run(run, params, baseline_snapshot)
    end)
  end

  defp execute_run(run, params, baseline_snapshot) do
    {:ok, _running} = Persistence.update_room_run(run.id, %{status: "running"})

    baseline =
      %{
        assignments_started: length(baseline_snapshot.assignments),
        assignments_completed:
          Enum.count(baseline_snapshot.assignments, &(&1.status == "completed"))
      }

    loop_run(run.id, run.room_id, params, baseline)
  rescue
    error -> {:error, run.id, error}
  catch
    kind, reason -> {:error, run.id, {kind, reason}}
  end

  defp loop_run(run_id, room_id, params, baseline) do
    with {:ok, snapshot} <- Collaboration.fetch_room_snapshot(room_id),
         {:ok, current_run} <- Persistence.fetch_room_run(room_id, run_id),
         :ok <- ensure_not_cancelled(current_run),
         metrics <- run_metrics(snapshot, baseline),
         :ok <- maybe_finish_run(run_id, snapshot, params, metrics),
         {:ok, action, dispatched_snapshot} <- RoomServer.dispatch_once(RoomServer.via(room_id)),
         metrics_after_dispatch <- run_metrics(dispatched_snapshot, baseline),
         {:ok, _updated} <-
           Persistence.update_room_run(run_id, metrics_to_attrs(metrics_after_dispatch)),
         {:ok, final_snapshot} <-
           wait_for_assignment_resolution(room_id, params.assignment_timeout_ms),
         final_metrics <- run_metrics(final_snapshot, baseline),
         {:ok, _updated} <- Persistence.update_room_run(run_id, metrics_to_attrs(final_metrics)) do
      case action do
        {:complete, completion} ->
          {:ok, run_id, %{status: "completed", result: %{reason: inspect(completion)}}}

        {:close, reason} ->
          {:ok, run_id, %{status: "cancelled", result: %{reason: inspect(reason)}}}

        _other ->
          Process.sleep(@poll_interval_ms)
          loop_run(run_id, room_id, params, baseline)
      end
    else
      {:finished, attrs} ->
        {:ok, run_id, attrs}

      {:error, reason} ->
        {:error, run_id, reason}
    end
  end

  defp maybe_finish_run(_run_id, snapshot, params, metrics) do
    cond do
      metrics.assignments_started >= params.max_assignments ->
        {:finished,
         %{
           status: "completed",
           result: %{reason: "max_assignments_reached"}
         }}

      until_satisfied?(snapshot, params.until, metrics) ->
        {:finished,
         %{
           status: "completed",
           result: %{reason: until_reason(params.until)}
         }}

      snapshot.room.status == "closed" ->
        {:finished, %{status: "cancelled", result: %{reason: "room_closed"}}}

      snapshot.room.status == "failed" ->
        {:finished, %{status: "failed", error: %{reason: "room_failed"}}}

      true ->
        :ok
    end
  end

  defp until_satisfied?(snapshot, %{"kind" => "policy_complete"}, _metrics) do
    snapshot.room.status == "completed"
  end

  defp until_satisfied?(_snapshot, %{"kind" => "assignment_count", "count" => count}, metrics) do
    metrics.assignments_completed >= count
  end

  defp until_satisfied?(_snapshot, _until, _metrics), do: false

  defp until_reason(%{"kind" => "policy_complete"}), do: "policy_complete"
  defp until_reason(%{"kind" => "assignment_count"}), do: "assignment_count"
  defp until_reason(_until), do: "completed"

  defp ensure_not_cancelled(%{status: "cancelled"}), do: {:error, :cancelled}
  defp ensure_not_cancelled(_run), do: :ok

  defp wait_for_assignment_resolution(room_id, assignment_timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + assignment_timeout_ms
    do_wait_for_assignment_resolution(room_id, deadline)
  end

  defp do_wait_for_assignment_resolution(room_id, deadline) do
    case Collaboration.fetch_room_snapshot(room_id) do
      {:ok, snapshot} ->
        open_assignments =
          Enum.filter(snapshot.assignments, &(&1.status in ["pending", "active"]))

        cond do
          open_assignments == [] ->
            {:ok, snapshot}

          System.monotonic_time(:millisecond) >= deadline ->
            expire_open_assignments(room_id, open_assignments)
            Collaboration.fetch_room_snapshot(room_id)

          true ->
            Process.sleep(@poll_interval_ms)
            do_wait_for_assignment_resolution(room_id, deadline)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_metrics(snapshot, baseline) do
    %{
      assignments_started: max(length(snapshot.assignments) - baseline.assignments_started, 0),
      assignments_completed:
        max(
          Enum.count(snapshot.assignments, &(&1.status == "completed")) -
            baseline.assignments_completed,
          0
        )
    }
  end

  defp metrics_to_attrs(metrics) do
    %{
      assignments_started: metrics.assignments_started,
      assignments_completed: metrics.assignments_completed
    }
  end

  defp normalize_run_attrs(attrs) do
    max_assignments = value(attrs, "max_assignments") || 1
    assignment_timeout_ms = value(attrs, "assignment_timeout_ms") || 60_000
    until = map_value(attrs, "until")

    with :ok <- validate_positive_integer(max_assignments, :invalid_max_assignments),
         :ok <- validate_positive_integer(assignment_timeout_ms, :invalid_assignment_timeout),
         :ok <- validate_until(until, max_assignments) do
      {:ok,
       %{
         max_assignments: max_assignments,
         assignment_timeout_ms: assignment_timeout_ms,
         until: until
       }}
    end
  end

  defp valid_until?(%{"kind" => "policy_complete"}), do: true

  defp valid_until?(%{"kind" => "assignment_count", "count" => count})
       when is_integer(count) and count > 0, do: true

  defp valid_until?(_until), do: false

  defp expire_open_assignments(room_id, assignments) do
    Enum.each(assignments, fn assignment ->
      _ = RoomServer.expire_assignment(RoomServer.via(room_id), assignment.id, "room run timeout")
    end)
  end

  defp validate_positive_integer(value, _reason) when is_integer(value) and value > 0, do: :ok
  defp validate_positive_integer(_value, reason), do: {:error, reason}

  defp validate_until(until, max_assignments) do
    cond do
      not valid_until?(until) ->
        {:error, :invalid_until}

      until["kind"] == "assignment_count" and until["count"] > max_assignments ->
        {:error, :invalid_until}

      true ->
        :ok
    end
  end

  defp initial_run_attrs(room_id, params) do
    %{
      run_id: new_run_id(),
      room_id: room_id,
      status: "queued",
      max_assignments: params.max_assignments,
      assignments_started: 0,
      assignments_completed: 0,
      assignment_timeout_ms: params.assignment_timeout_ms,
      until: params.until,
      result: nil,
      error: nil
    }
  end

  defp put_task(state, run_id, task) do
    %{state | tasks: Map.put(state.tasks, run_id, task)}
  end

  defp put_ref(state, ref, run_id) do
    %{state | refs: Map.put(state.refs, ref, run_id)}
  end

  defp drop_task(state, run_id) do
    task = Map.get(state.tasks, run_id)

    refs =
      case task do
        %Task{ref: ref} -> Map.delete(state.refs, ref)
        _other -> state.refs
      end

    %{state | tasks: Map.delete(state.tasks, run_id), refs: refs}
  end

  defp drop_task_by_ref(state, ref) do
    case Map.get(state.refs, ref) do
      nil -> state
      run_id -> drop_task(state, run_id)
    end
  end

  defp stop_task(nil), do: :ok
  defp stop_task(%Task{pid: pid}) when is_pid(pid), do: Process.exit(pid, :kill)

  defp new_run_id do
    suffix =
      6
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    "run-#{suffix}"
  end

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp map_value(map, key) do
    case value(map, key) do
      %{} = nested -> nested
      _other -> %{}
    end
  end

  defp existing_atom_key(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
