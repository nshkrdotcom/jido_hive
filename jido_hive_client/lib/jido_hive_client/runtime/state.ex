defmodule JidoHiveClient.Runtime.State do
  @moduledoc false

  @default_recent_job_limit 20

  defstruct client_id: nil,
            connection_status: :starting,
            identity: %{},
            current_job: nil,
            recent_jobs: [],
            metrics: %{
              jobs_received: 0,
              jobs_completed: 0,
              jobs_failed: 0,
              reconnect_count: 0
            },
            last_error: nil,
            updated_at: nil,
            recent_job_limit: @default_recent_job_limit

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    identity = identity_from_opts(opts)
    client_id = "#{identity.workspace_id}:#{identity.target_id}"

    %__MODULE__{
      client_id: client_id,
      identity: identity,
      updated_at: DateTime.utc_now(),
      recent_job_limit: Keyword.get(opts, :recent_job_limit, @default_recent_job_limit)
    }
  end

  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = state) do
    %{
      client_id: state.client_id,
      connection_status: state.connection_status,
      identity: state.identity,
      current_job: state.current_job,
      recent_jobs: state.recent_jobs,
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

  @spec job_received(t(), map()) :: t()
  def job_received(%__MODULE__{} = state, job) when is_map(job) do
    state
    |> update_metric(:jobs_received)
    |> Map.put(:current_job, current_job(job, "received"))
    |> touch()
  end

  @spec job_started(t(), map()) :: t()
  def job_started(%__MODULE__{} = state, job) when is_map(job) do
    state
    |> Map.put(:connection_status, :executing)
    |> Map.put(:current_job, current_job(job, "running"))
    |> touch()
  end

  @spec job_finished(t(), map(), map()) :: t()
  def job_finished(%__MODULE__{} = state, job, result) when is_map(job) and is_map(result) do
    state
    |> update_metric(:jobs_completed)
    |> Map.put(:connection_status, :ready)
    |> Map.put(:current_job, nil)
    |> Map.put(:last_error, nil)
    |> put_recent_job(recent_job(job, result))
    |> touch()
  end

  @spec job_failed(t(), map(), term()) :: t()
  def job_failed(%__MODULE__{} = state, job, reason) when is_map(job) do
    state
    |> update_metric(:jobs_failed)
    |> Map.put(:connection_status, :ready)
    |> Map.put(:current_job, nil)
    |> Map.put(:last_error, last_error(job, reason))
    |> put_recent_job(recent_job(job, %{"status" => "failed"}))
    |> touch()
  end

  defp put_recent_job(%__MODULE__{} = state, job) do
    jobs =
      [job | state.recent_jobs]
      |> Enum.take(state.recent_job_limit)

    %{state | recent_jobs: jobs}
  end

  defp update_metric(%__MODULE__{} = state, key) do
    update_in(state.metrics, &Map.update!(&1, key, fn value -> value + 1 end))
  end

  defp current_job(job, status) do
    %{
      job_id: Map.get(job, "job_id"),
      room_id: Map.get(job, "room_id"),
      participant_id: Map.get(job, "participant_id"),
      participant_role: Map.get(job, "participant_role"),
      status: status
    }
  end

  defp recent_job(job, result) do
    %{
      job_id: Map.get(job, "job_id"),
      room_id: Map.get(job, "room_id"),
      participant_id: Map.get(job, "participant_id"),
      participant_role: Map.get(job, "participant_role"),
      status: Map.get(result, "status", "completed"),
      summary: Map.get(result, "summary"),
      completed_at: DateTime.utc_now()
    }
  end

  defp last_error(job, reason) do
    %{
      job_id: Map.get(job, "job_id"),
      room_id: Map.get(job, "room_id"),
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
      capability_id: Keyword.get(opts, :capability_id, "codex.exec.session"),
      workspace_root: Keyword.get(opts, :workspace_root, File.cwd!()),
      provider: normalize_atomish(Keyword.get(executor_opts, :provider, :codex)),
      model: Keyword.get(executor_opts, :model),
      runtime_id: normalize_atomish(Keyword.get(opts, :runtime_id, :asm))
    }
  end

  defp normalize_executor({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_executor(module) when is_atom(module), do: {module, []}
  defp normalize_executor(_other), do: {JidoHiveClient.Executor.Session, [provider: :codex]}

  defp normalize_atomish(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_atomish(value) when is_binary(value), do: value
  defp normalize_atomish(_other), do: nil
end
