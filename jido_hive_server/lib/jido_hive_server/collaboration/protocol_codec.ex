defmodule JidoHiveServer.Collaboration.ProtocolCodec do
  @moduledoc false

  @job_start_v2 "jido_hive/job.start.v2"

  @spec decode_inbound(String.t(), map(), String.t()) ::
          {:ok, {:relay_hello | :target_register | :job_result, map()}} | {:error, term()}
  def decode_inbound(event, payload, workspace_id)
      when is_binary(event) and is_map(payload) and is_binary(workspace_id) do
    with {:ok, type} <- event_type(event),
         {:ok, message} <- unwrap_message(type, payload),
         message <- normalize_value(message),
         message <- inject_workspace(type, message, workspace_id),
         :ok <- validate(type, message) do
      {:ok, {type, normalize_defaults(type, message)}}
    end
  end

  def decode_inbound(_event, _payload, _workspace_id), do: {:error, :invalid_payload}

  @spec encode_job_start(map()) :: map()
  def encode_job_start(job) when is_map(job) do
    job
    |> normalize_value()
    |> Map.put_new("schema_version", @job_start_v2)
  end

  defp event_type("relay.hello"), do: {:ok, :relay_hello}
  defp event_type("relay.hello.v2"), do: {:ok, :relay_hello}
  defp event_type("target.upsert"), do: {:ok, :target_register}
  defp event_type("target.register"), do: {:ok, :target_register}
  defp event_type("job.result"), do: {:ok, :job_result}
  defp event_type("job.result.v2"), do: {:ok, :job_result}
  defp event_type(_other), do: {:error, :unsupported_event}

  defp unwrap_message(:relay_hello, %{"hello" => %{} = hello}), do: {:ok, hello}
  defp unwrap_message(:target_register, %{"target" => %{} = target}), do: {:ok, target}
  defp unwrap_message(:job_result, %{"result" => %{} = result}), do: {:ok, result}
  defp unwrap_message(_type, %{} = payload), do: {:ok, payload}

  defp inject_workspace(type, payload, workspace_id)
       when type in [:relay_hello, :target_register] do
    Map.put(payload, "workspace_id", workspace_id)
  end

  defp inject_workspace(_type, payload, _workspace_id), do: payload

  defp normalize_defaults(:relay_hello, payload) do
    payload
    |> Map.put_new("client_version", "0.1.0")
  end

  defp normalize_defaults(:target_register, payload) do
    payload
    |> Map.put_new("runtime_driver", "asm")
    |> Map.put_new("provider", "codex")
  end

  defp normalize_defaults(:job_result, payload) do
    payload
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

  defp validate(:relay_hello, payload) do
    require_fields(payload, ["participant_id", "participant_role", "workspace_id"])
  end

  defp validate(:target_register, payload) do
    case require_fields(payload, ["target_id", "capability_id", "workspace_id"]) do
      :ok ->
        validate_map_fields(payload, [
          "execution_surface",
          "execution_environment",
          "provider_options"
        ])

      error ->
        error
    end
  end

  defp validate(:job_result, payload) do
    case require_fields(payload, ["job_id", "room_id", "status"]) do
      :ok -> validate_map_field(payload, "execution")
      error -> error
    end
  end

  defp require_fields(payload, fields) do
    case Enum.find(fields, &missing_field?(payload, &1)) do
      nil -> :ok
      field -> {:error, {:missing_field, field}}
    end
  end

  defp validate_map_field(payload, field) when is_map(payload) do
    case Map.get(payload, field) do
      nil -> :ok
      value when is_map(value) -> :ok
      _other -> {:error, {:invalid_field, field}}
    end
  end

  defp validate_map_fields(payload, fields) when is_map(payload) and is_list(fields) do
    Enum.reduce_while(fields, :ok, fn field, :ok ->
      case validate_map_field(payload, field) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp missing_field?(payload, field) do
    case Map.get(payload, field) do
      value when is_binary(value) -> String.trim(value) == ""
      nil -> true
      _other -> false
    end
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
end
