defmodule JidoHiveClient.Boundary.ProtocolCodec do
  @moduledoc false

  alias JidoHiveClient.ExecutionContract

  @assignment_start_v1 "jido_hive/assignment.start.v1"
  @contribution_submit_v1 "jido_hive/contribution.submit.v1"
  @required_assignment_fields ~w(assignment_id room_id)

  @spec normalize_assignment_start(map()) :: {:ok, map()} | {:error, term()}
  def normalize_assignment_start(payload) when is_map(payload) do
    with {:ok, assignment} <- unwrap_assignment(payload),
         assignment <- normalize_value(assignment),
         :ok <- validate_map_field(assignment, "session"),
         :ok <- validate_map_field(assignment, "contribution_contract"),
         :ok <- validate_map_field(assignment, "context_view"),
         :ok <- validate_nested_session(assignment),
         :ok <- require_fields(assignment, @required_assignment_fields) do
      {:ok,
       assignment
       |> Map.put_new("session", %{})
       |> Map.put_new("contribution_contract", %{})
       |> Map.put_new("context_view", %{})
       |> Map.put_new("status", "running")}
    end
  end

  def normalize_assignment_start(_other), do: {:error, :invalid_payload}

  @spec normalize_contribution(map(), map()) :: map()
  def normalize_contribution(result, defaults \\ %{}) when is_map(result) and is_map(defaults) do
    defaults = normalize_value(defaults)

    result
    |> normalize_value()
    |> Map.put_new("schema_version", @contribution_submit_v1)
    |> Map.put_new("room_id", defaults["room_id"])
    |> Map.put_new("assignment_id", defaults["assignment_id"])
    |> Map.put_new("participant_id", defaults["participant_id"])
    |> Map.put_new("participant_role", defaults["participant_role"])
    |> Map.put_new("target_id", defaults["target_id"])
    |> Map.put_new("capability_id", defaults["capability_id"])
    |> Map.put_new("contribution_type", "reasoning")
    |> Map.put_new("authority_level", "advisory")
    |> Map.put_new("summary", "")
    |> Map.put_new("context_objects", [])
    |> Map.put_new("artifacts", [])
    |> Map.put_new("events", [])
    |> Map.put_new("tool_events", [])
    |> Map.put_new("approvals", [])
    |> Map.put_new("execution", %{})
    |> Map.put_new("status", "completed")
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

  @spec participant_payload(map()) :: map()
  def participant_payload(attrs) when is_map(attrs) do
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

  defp unwrap_assignment(payload) when is_map(payload) do
    payload = normalize_value(payload)

    case payload do
      %{"schema_version" => @assignment_start_v1, "assignment" => %{} = assignment} ->
        {:ok, assignment}

      %{"assignment" => %{} = assignment} ->
        {:ok, assignment}

      %{} = assignment ->
        {:ok, assignment}
    end
  end

  defp require_fields(assignment, fields) when is_map(assignment) do
    case Enum.find(fields, &missing_field?(assignment, &1)) do
      nil -> :ok
      field -> {:error, {:missing_field, field}}
    end
  end

  defp validate_nested_session(assignment) do
    session = Map.get(assignment, "session", %{})

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

  defp missing_field?(assignment, field) do
    case Map.get(assignment, field) do
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
