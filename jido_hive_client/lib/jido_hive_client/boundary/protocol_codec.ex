defmodule JidoHiveClient.Boundary.ProtocolCodec do
  @moduledoc false

  alias JidoHiveClient.ExecutionContract

  @job_start_v2 "jido_hive/job_start.v2"
  @job_result_v1 "jido_hive/job_result.v1"

  @required_job_fields ~w(job_id room_id)

  @spec normalize_job_start(map()) :: {:ok, map()} | {:error, term()}
  def normalize_job_start(payload) when is_map(payload) do
    with {:ok, job} <- unwrap_job(payload),
         job <- normalize_value(job),
         :ok <- require_fields(job, @required_job_fields),
         :ok <- validate_map_field(job, "session"),
         :ok <- validate_map_field(job, "collaboration_envelope"),
         :ok <- validate_nested_session(job) do
      {:ok,
       job
       |> Map.put_new("session", %{})
       |> Map.put_new("collaboration_envelope", %{})}
    end
  end

  def normalize_job_start(_other), do: {:error, :invalid_payload}

  @spec normalize_job_result(map(), map()) :: map()
  def normalize_job_result(result, defaults \\ %{}) when is_map(result) and is_map(defaults) do
    defaults = normalize_value(defaults)

    result
    |> normalize_value()
    |> Map.put_new("schema_version", @job_result_v1)
    |> Map.put_new("job_id", defaults["job_id"])
    |> Map.put_new("room_id", defaults["room_id"])
    |> Map.put_new("target_id", defaults["target_id"])
    |> Map.put_new("capability_id", defaults["capability_id"])
    |> Map.put_new("participant_id", defaults["participant_id"])
    |> Map.put_new("participant_role", defaults["participant_role"])
    |> Map.put_new("status", "completed")
    |> Map.put_new("summary", "")
    |> Map.put_new("actions", [])
    |> Map.put_new("tool_events", [])
    |> Map.put_new("events", [])
    |> Map.put_new("approvals", [])
    |> Map.put_new("artifacts", [])
    |> Map.update("execution", %{}, fn
      execution when is_map(execution) -> execution
      _other -> %{}
    end)
  end

  @spec hello_payload(map()) :: map()
  def hello_payload(attrs) when is_map(attrs) do
    %{
      "workspace_id" => value(attrs, :workspace_id),
      "user_id" => value(attrs, :user_id),
      "participant_id" => value(attrs, :participant_id),
      "participant_role" => value(attrs, :participant_role),
      "client_version" => "0.1.0"
    }
    |> compact_map()
  end

  @spec target_payload(map()) :: map()
  def target_payload(attrs) when is_map(attrs) do
    executor_opts =
      case value(attrs, :executor) do
        {_module, opts} when is_list(opts) -> opts
        _other -> []
      end

    workspace_root = value(attrs, :workspace_root) || File.cwd!()

    %{
      "workspace_id" => value(attrs, :workspace_id),
      "user_id" => value(attrs, :user_id),
      "participant_id" => value(attrs, :participant_id),
      "participant_role" => value(attrs, :participant_role),
      "target_id" => value(attrs, :target_id),
      "capability_id" => value(attrs, :capability_id),
      "runtime_driver" => value(attrs, :runtime_id) || "asm"
    }
    |> Map.merge(ExecutionContract.target_registration_payload(executor_opts, workspace_root))
    |> compact_map()
  end

  defp unwrap_job(payload) when is_map(payload) do
    payload = normalize_value(payload)

    case payload do
      %{"schema_version" => @job_start_v2, "job" => %{} = job} -> {:ok, job}
      %{"job" => %{} = job} -> {:ok, job}
      %{} = job -> {:ok, job}
    end
  end

  defp require_fields(job, fields) when is_map(job) do
    case Enum.find(fields, &missing_field?(job, &1)) do
      nil -> :ok
      field -> {:error, {:missing_field, field}}
    end
  end

  defp validate_nested_session(job) do
    session = Map.get(job, "session", %{})

    validate_map_fields(session, [
      "execution_surface",
      "execution_environment",
      "provider_options"
    ])
  end

  defp validate_map_field(map, field) when is_map(map) do
    case Map.get(map, field) do
      nil -> :ok
      value when is_map(value) -> :ok
      _other -> {:error, {:invalid_field, field}}
    end
  end

  defp validate_map_fields(map, fields) when is_map(map) and is_list(fields) do
    Enum.reduce_while(fields, :ok, fn field, :ok ->
      case validate_map_field(map, field) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp missing_field?(job, field) do
    case Map.get(job, field) do
      value when is_binary(value) -> String.trim(value) == ""
      nil -> true
      _other -> false
    end
  end

  defp value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp normalize_value(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} -> {to_string(key), normalize_value(nested_value)} end)
    |> Map.new()
  end

  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value) when is_boolean(value), do: value
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value), do: value

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
