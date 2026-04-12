defmodule JidoHiveWorkerRuntime.Runtime.State do
  @moduledoc false

  @default_recent_assignment_limit 20

  defstruct client_id: nil,
            connection_status: :starting,
            identity: %{},
            current_assignment: nil,
            recent_assignments: [],
            metrics: %{
              assignments_received: 0,
              assignments_completed: 0,
              assignments_failed: 0,
              reconnect_count: 0
            },
            last_error: nil,
            updated_at: nil,
            recent_assignment_limit: @default_recent_assignment_limit

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    identity = identity_from_opts(opts)
    client_id = "#{identity.workspace_id}:#{identity.target_id}"

    %__MODULE__{
      client_id: client_id,
      identity: identity,
      updated_at: DateTime.utc_now(),
      recent_assignment_limit:
        Keyword.get(opts, :recent_assignment_limit, @default_recent_assignment_limit)
    }
  end

  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = state) do
    %{
      client_id: state.client_id,
      connection_status: state.connection_status,
      identity: state.identity,
      current_assignment: state.current_assignment,
      recent_assignments: state.recent_assignments,
      metrics: state.metrics,
      last_error: state.last_error,
      updated_at: state.updated_at
    }
  end

  @spec connection_changed(t(), atom()) :: t()
  def connection_changed(%__MODULE__{} = state, status) when is_atom(status) do
    reconnect_count =
      if state.connection_status in [:ready, :executing] and status in [:waiting_socket, :joining] do
        state.metrics.reconnect_count + 1
      else
        state.metrics.reconnect_count
      end

    state
    |> put_in([Access.key(:metrics), Access.key(:reconnect_count)], reconnect_count)
    |> Map.put(:connection_status, status)
    |> touch()
  end

  @spec assignment_received(t(), map()) :: t()
  def assignment_received(%__MODULE__{} = state, assignment) when is_map(assignment) do
    state
    |> update_metric(:assignments_received)
    |> Map.put(:current_assignment, current_assignment(assignment, "received"))
    |> touch()
  end

  @spec assignment_started(t(), map()) :: t()
  def assignment_started(%__MODULE__{} = state, assignment) when is_map(assignment) do
    state
    |> Map.put(:connection_status, :executing)
    |> Map.put(:current_assignment, current_assignment(assignment, "running"))
    |> touch()
  end

  @spec assignment_finished(t(), map(), map()) :: t()
  def assignment_finished(%__MODULE__{} = state, assignment, contribution)
      when is_map(assignment) and is_map(contribution) do
    state
    |> update_metric(:assignments_completed)
    |> Map.put(:connection_status, :ready)
    |> Map.put(:current_assignment, nil)
    |> Map.put(:last_error, nil)
    |> put_recent_assignment(recent_assignment(assignment, contribution))
    |> touch()
  end

  @spec assignment_failed(t(), map(), term()) :: t()
  def assignment_failed(%__MODULE__{} = state, assignment, reason) when is_map(assignment) do
    state
    |> update_metric(:assignments_failed)
    |> Map.put(:connection_status, :ready)
    |> Map.put(:current_assignment, nil)
    |> Map.put(:last_error, last_error(assignment, reason))
    |> put_recent_assignment(recent_assignment(assignment, %{"meta" => %{"status" => "failed"}}))
    |> touch()
  end

  defp put_recent_assignment(%__MODULE__{} = state, assignment) do
    assignments =
      [assignment | state.recent_assignments]
      |> Enum.take(state.recent_assignment_limit)

    %{state | recent_assignments: assignments}
  end

  defp update_metric(%__MODULE__{} = state, key) do
    update_in(state.metrics, &Map.update!(&1, key, fn value -> value + 1 end))
  end

  defp current_assignment(assignment, status) do
    %{
      assignment_id: Map.get(assignment, "id"),
      room_id: Map.get(assignment, "room_id"),
      participant_id: Map.get(assignment, "participant_id"),
      participant_role: Map.get(assignment, "participant_role"),
      phase: Map.get(assignment, "phase"),
      status: status
    }
  end

  defp recent_assignment(assignment, contribution) do
    %{
      assignment_id: Map.get(assignment, "id"),
      room_id: Map.get(assignment, "room_id"),
      participant_id: Map.get(assignment, "participant_id"),
      participant_role: Map.get(assignment, "participant_role"),
      phase: Map.get(assignment, "phase"),
      status:
        get_in(contribution, ["meta", "status"]) || Map.get(contribution, "status", "completed"),
      summary: get_in(contribution, ["payload", "summary"]) || Map.get(contribution, "summary"),
      contribution_type: Map.get(contribution, "kind"),
      completed_at: DateTime.utc_now()
    }
  end

  defp last_error(assignment, reason) do
    %{
      assignment_id: Map.get(assignment, "id"),
      room_id: Map.get(assignment, "room_id"),
      reason: inspect(reason),
      occurred_at: DateTime.utc_now()
    }
  end

  defp touch(%__MODULE__{} = state), do: %{state | updated_at: DateTime.utc_now()}

  defp identity_from_opts(opts) do
    {_module, executor_opts} = normalize_executor(Keyword.get(opts, :executor))

    %{
      workspace_id: Keyword.get(opts, :workspace_id, "workspace-local"),
      user_id: Keyword.get(opts, :user_id, "user-local"),
      participant_id: Keyword.get(opts, :participant_id, "participant-local"),
      participant_role: Keyword.get(opts, :participant_role, "worker"),
      target_id: Keyword.get(opts, :target_id, "target-local"),
      capability_id: Keyword.get(opts, :capability_id, "workspace.exec.session"),
      workspace_root: Keyword.get(opts, :workspace_root, File.cwd!()),
      provider: normalize_atomish(Keyword.get(executor_opts, :provider, :codex)),
      model: Keyword.get(executor_opts, :model),
      runtime_id: normalize_atomish(Keyword.get(opts, :runtime_id, :asm))
    }
  end

  defp normalize_executor({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_executor(module) when is_atom(module), do: {module, []}

  defp normalize_executor(_other),
    do: {JidoHiveWorkerRuntime.Executor.Session, [provider: :codex]}

  defp normalize_atomish(nil), do: nil
  defp normalize_atomish(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_atomish(value) when is_binary(value), do: value
  defp normalize_atomish(_other), do: nil
end
