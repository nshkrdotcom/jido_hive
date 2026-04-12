defmodule JidoHiveWorkerRuntime.Boundary.ProtocolCodec do
  @moduledoc false

  alias JidoHiveWorkerRuntime.ExecutionContract

  @spec room_join_payload(map(), integer() | nil) :: map()
  def room_join_payload(attrs, last_seen_event_sequence \\ nil) when is_map(attrs) do
    executor_opts =
      case value(attrs, :executor) do
        {_module, opts} when is_list(opts) -> opts
        _other -> []
      end

    workspace_root = value(attrs, :workspace_root) || File.cwd!()

    participant_meta =
      %{
        "role" => value(attrs, :participant_role),
        "target_id" => value(attrs, :target_id),
        "capability_id" => value(attrs, :capability_id),
        "workspace_id" => value(attrs, :workspace_id),
        "user_id" => value(attrs, :user_id),
        "runtime_driver" => value(attrs, :runtime_id) || "asm"
      }
      |> Map.merge(ExecutionContract.target_registration_payload(executor_opts, workspace_root))
      |> compact_map()

    session =
      %{"mode" => "participant"}
      |> maybe_put("last_seen_event_sequence", last_seen_event_sequence)

    %{
      "session" => session,
      "participant" => %{
        "id" => value(attrs, :participant_id),
        "kind" => value(attrs, :participant_kind) || "agent",
        "handle" => value(attrs, :participant_handle) || value(attrs, :participant_id),
        "meta" => participant_meta
      }
    }
  end

  @spec target_registration_payload(map()) :: map()
  def target_registration_payload(attrs) when is_map(attrs) do
    executor_opts =
      case value(attrs, :executor) do
        {_module, opts} when is_list(opts) -> opts
        _other -> []
      end

    workspace_root = value(attrs, :workspace_root) || File.cwd!()

    %{
      "target_id" => value(attrs, :target_id),
      "workspace_id" => value(attrs, :workspace_id),
      "participant_id" => value(attrs, :participant_id),
      "participant_role" => value(attrs, :participant_role),
      "capability_id" => value(attrs, :capability_id),
      "runtime_driver" => value(attrs, :runtime_id) || "asm",
      "user_id" => value(attrs, :user_id)
    }
    |> Map.merge(ExecutionContract.target_registration_payload(executor_opts, workspace_root))
    |> compact_map()
  end

  @spec normalize_assignment_offer(map()) :: {:ok, map()} | {:error, term()}
  def normalize_assignment_offer(payload) when is_map(payload) do
    with {:ok, assignment} <- unwrap_assignment(payload),
         assignment <- normalize_value(assignment),
         :ok <- validate_map_field(assignment, "payload"),
         :ok <- require_fields(assignment, ~w(id room_id participant_id)) do
      assignment_payload = map_value(assignment, "payload")
      assignment_meta = map_value(assignment, "meta")
      participant_meta = map_value(assignment_meta, "participant_meta")

      {:ok,
       assignment
       |> Map.put("payload", assignment_payload)
       |> Map.put("meta", assignment_meta)
       |> Map.put("context", map_value(assignment_payload, "context"))
       |> Map.put("prompt_config", map_value(assignment_payload, "prompt_config"))
       |> Map.put("output_contract", map_value(assignment_payload, "output_contract"))
       |> Map.put("executor", map_value(assignment_payload, "executor"))
       |> Map.put("extension", map_value(assignment_payload, "extension"))
       |> Map.put("status", Map.get(assignment, "status", "pending"))
       |> maybe_put("phase", Map.get(assignment_payload, "phase"))
       |> maybe_put("objective", Map.get(assignment_payload, "objective"))
       |> maybe_put("participant_role", Map.get(participant_meta, "role"))
       |> maybe_put("target_id", Map.get(participant_meta, "target_id"))
       |> maybe_put("capability_id", Map.get(participant_meta, "capability_id"))}
    end
  end

  def normalize_assignment_offer(_other), do: {:error, :invalid_payload}

  @spec normalize_contribution(map(), map()) :: map()
  def normalize_contribution(result, defaults \\ %{}) when is_map(result) and is_map(defaults) do
    result = normalize_value(result)
    defaults = normalize_value(defaults)
    relation_target_filter = relation_target_filter(defaults)

    context_objects =
      result
      |> context_object_source()
      |> sanitize_context_objects(relation_target_filter)

    payload =
      map_value(result, "payload")
      |> maybe_put("summary", value(result, "summary"))
      |> maybe_put("text", value(result, "text") || value(result, "body"))
      |> maybe_put("title", value(result, "title"))
      |> maybe_put("context_objects", context_objects)
      |> maybe_put("artifacts", list_value(result, "artifacts"))
      |> maybe_put("extension", map_value(result, "extension"))

    meta =
      map_value(result, "meta")
      |> maybe_put("participant_role", defaults["participant_role"])
      |> maybe_put("target_id", defaults["target_id"])
      |> maybe_put("capability_id", defaults["capability_id"])
      |> maybe_put("authority_level", value(result, "authority_level"))
      |> maybe_put("events", list_value(result, "events"))
      |> maybe_put("tool_events", list_value(result, "tool_events"))
      |> maybe_put("approvals", list_value(result, "approvals"))
      |> maybe_put("execution", map_value(result, "execution"))
      |> maybe_put("status", value(result, "status") || "completed")

    %{}
    |> maybe_put("id", value(result, "id") || value(result, "contribution_id"))
    |> maybe_put("room_id", defaults["room_id"])
    |> maybe_put("assignment_id", defaults["assignment_id"] || defaults["id"])
    |> maybe_put("participant_id", defaults["participant_id"])
    |> maybe_put(
      "kind",
      value(result, "kind") || value(result, "contribution_type") || "reasoning"
    )
    |> Map.put("payload", payload)
    |> Map.put("meta", meta)
  end

  @spec api_base_url(String.t()) :: String.t()
  def api_base_url(socket_url) when is_binary(socket_url) do
    uri = URI.parse(socket_url)

    scheme =
      case uri.scheme do
        "wss" -> "https"
        "ws" -> "http"
        "https" -> "https"
        _other -> "http"
      end

    path =
      uri.path
      |> to_string()
      |> String.replace_suffix("/socket/websocket", "/api")
      |> then(fn
        "" -> "/api"
        value -> value
      end)

    %URI{scheme: scheme, host: uri.host, port: uri.port, path: path}
    |> URI.to_string()
    |> String.trim_trailing("/")
  end

  defp unwrap_assignment(payload) when is_map(payload) do
    payload = normalize_value(payload)

    case payload do
      %{"data" => %{} = assignment} -> {:ok, assignment}
      %{"assignment" => %{} = assignment} -> {:ok, assignment}
      %{} = assignment -> {:ok, assignment}
    end
  end

  defp require_fields(assignment, fields) when is_map(assignment) do
    case Enum.find(fields, &missing_field?(assignment, &1)) do
      nil -> :ok
      field -> {:error, {:missing_field, field}}
    end
  end

  defp validate_map_field(map, field) when is_map(map) do
    case Map.get(map, field) do
      nil -> :ok
      value when is_map(value) -> :ok
      _other -> {:error, {:invalid_field, field}}
    end
  end

  defp missing_field?(assignment, field) do
    case Map.get(assignment, field) do
      value when is_binary(value) -> String.trim(value) == ""
      nil -> true
      _other -> false
    end
  end

  defp relation_target_filter(defaults) do
    case get_in(defaults, ["context", "context_objects"]) do
      context_objects when is_list(context_objects) ->
        allowlist =
          context_objects
          |> Enum.map(&(value(&1, "context_id") || value(&1, "id")))
          |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
          |> MapSet.new()

        {:allowlist, allowlist}

      _other ->
        :pass_through
    end
  end

  defp context_object_source(result) do
    cond do
      is_list(value(result, "context_objects")) ->
        value(result, "context_objects")

      is_list(get_in(result, ["payload", "context_objects"])) ->
        get_in(result, ["payload", "context_objects"])

      true ->
        []
    end
  end

  defp sanitize_context_objects(context_objects, relation_target_filter)
       when is_list(context_objects) do
    Enum.map(context_objects, fn
      %{} = context_object ->
        Map.update(
          normalize_value(context_object),
          "relations",
          [],
          &sanitize_relations(&1, relation_target_filter)
        )

      other ->
        other
    end)
  end

  defp sanitize_context_objects(_other, _relation_target_filter), do: []

  defp sanitize_relations(relations, relation_target_filter) when is_list(relations) do
    relations
    |> Enum.map(&normalize_relation/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&allowed_relation_target?(&1, relation_target_filter))
  end

  defp sanitize_relations(_other, _relation_target_filter), do: []

  defp normalize_relation(relation) when is_map(relation) do
    normalized_relation = %{
      "relation" =>
        value(relation, "relation") || value(relation, "relation_type") || value(relation, "type"),
      "target_id" => value(relation, "target_id") || value(relation, "to")
    }

    if valid_relation?(normalized_relation), do: normalized_relation, else: nil
  end

  defp normalize_relation(_relation), do: nil

  defp allowed_relation_target?(%{"target_id" => _target_id}, :pass_through), do: true
  defp allowed_relation_target?(nil, _relation_target_filter), do: false

  defp allowed_relation_target?(%{"target_id" => target_id}, {:allowlist, allowlist}) do
    MapSet.member?(allowlist, target_id)
  end

  defp valid_relation?(%{"relation" => relation, "target_id" => target_id}) do
    valid_relation_component?(relation) and valid_relation_component?(target_id)
  end

  defp valid_relation?(_relation), do: false

  defp valid_relation_component?(value) when is_binary(value) do
    case String.trim(value) do
      "" -> false
      normalized -> String.downcase(normalized) not in ["nil", "null"]
    end
  end

  defp valid_relation_component?(_value), do: false

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

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, _key, %{} = value) when map_size(value) == 0, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp map_value(map, key) when is_map(map) do
    case value(map, key) do
      %{} = value -> normalize_value(value)
      _other -> %{}
    end
  end

  defp list_value(map, key) when is_map(map) do
    case value(map, key) do
      values when is_list(values) -> normalize_value(values)
      _other -> []
    end
  end

  defp value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) ||
      case existing_atom_key(key) do
        nil -> nil
        atom_key -> Map.get(map, atom_key)
      end
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
