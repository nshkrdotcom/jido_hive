defmodule JidoHiveServer.Collaboration.ProtocolCodec do
  @moduledoc false

  @assignment_start_v1 "jido_hive/assignment.start.v1"

  @spec decode_inbound(String.t(), map(), String.t()) ::
          {:ok, {:relay_hello | :participant_upsert | :contribution_submit, map()}}
          | {:error, term()}
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

  @spec encode_assignment_start(map()) :: map()
  def encode_assignment_start(assignment) when is_map(assignment) do
    assignment
    |> normalize_value()
    |> Map.put_new("schema_version", @assignment_start_v1)
  end

  defp event_type("relay.hello"), do: {:ok, :relay_hello}
  defp event_type("participant.upsert"), do: {:ok, :participant_upsert}
  defp event_type("contribution.submit"), do: {:ok, :contribution_submit}
  defp event_type(_other), do: {:error, :unsupported_event}

  defp unwrap_message(:relay_hello, %{"hello" => %{} = hello}), do: {:ok, hello}

  defp unwrap_message(:participant_upsert, %{"participant" => %{} = participant}),
    do: {:ok, participant}

  defp unwrap_message(:contribution_submit, %{"contribution" => %{} = contribution}),
    do: {:ok, contribution}

  defp unwrap_message(_type, %{} = payload), do: {:ok, payload}

  defp inject_workspace(type, payload, workspace_id)
       when type in [:relay_hello, :participant_upsert] do
    Map.put(payload, "workspace_id", workspace_id)
  end

  defp inject_workspace(_type, payload, _workspace_id), do: payload

  defp normalize_defaults(:relay_hello, payload) do
    Map.put_new(payload, "client_version", "0.1.0")
  end

  defp normalize_defaults(:participant_upsert, payload) do
    payload
    |> Map.put_new("runtime_driver", "asm")
    |> Map.put_new("provider", "codex")
  end

  defp normalize_defaults(:contribution_submit, payload) do
    payload
    |> Map.put_new("context_objects", [])
    |> Map.put_new("artifacts", [])
    |> Map.put_new("events", [])
    |> Map.put_new("tool_events", [])
    |> Map.put_new("approvals", [])
    |> Map.put_new("execution", %{})
    |> Map.put_new("status", "completed")
    |> Map.put_new("schema_version", "jido_hive/contribution.submit.v1")
  end

  defp validate(:relay_hello, payload) do
    require_fields(payload, ["participant_id", "participant_role", "workspace_id"])
  end

  defp validate(:participant_upsert, payload) do
    case require_fields(payload, [
           "target_id",
           "capability_id",
           "participant_id",
           "participant_role",
           "workspace_id"
         ]) do
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

  defp validate(:contribution_submit, payload) do
    case require_fields(payload, [
           "room_id",
           "participant_id",
           "participant_role",
           "contribution_type",
           "authority_level",
           "summary"
         ]) do
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

  defp normalize_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)

  defp normalize_value(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} -> {to_string(key), normalize_value(nested_value)} end)
    |> Map.new()
  end

  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value) when is_boolean(value), do: value
  defp normalize_value(nil), do: nil
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value), do: value
end
