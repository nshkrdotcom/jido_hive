defmodule JidoHive.SharedMemoryFacade do
  @moduledoc """
  Explicit shared-memory facade over governed memory scopes.
  """

  defmodule Grant do
    @moduledoc "Shared-memory grant."
    @enforce_keys [
      :grant_ref,
      :tenant_ref,
      :installation_ref,
      :agent_ref,
      :memory_scope_ref,
      :operations,
      :guard_policy_ref,
      :authority_ref,
      :trace_ref,
      :redaction_posture
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  defmodule MemoryIntent do
    @moduledoc "Shared-memory operation intent."
    @enforce_keys [
      :intent_ref,
      :tenant_ref,
      :installation_ref,
      :agent_ref,
      :memory_scope_ref,
      :operation,
      :memory_ref,
      :guard_decision_ref,
      :idempotency_key,
      :trace_ref,
      :redaction_posture
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  defmodule Decision do
    @moduledoc "Shared-memory authorization decision."
    @enforce_keys [
      :decision_ref,
      :tenant_ref,
      :installation_ref,
      :agent_ref,
      :memory_scope_ref,
      :operation,
      :memory_ref,
      :trace_ref,
      :decision,
      :redaction_posture
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  @operations [:shared_read, :shared_write, :handoff, :revocation]
  @raw_keys [
    :body,
    :memory_body,
    :private_state,
    :provider_payload,
    :raw_body,
    :raw_memory,
    :secret,
    :skill_private_state,
    :tool_output,
    "body",
    "memory_body",
    "private_state",
    "provider_payload",
    "raw_body",
    "raw_memory",
    "secret",
    "skill_private_state",
    "tool_output"
  ]

  @grant_required Grant.__struct__() |> Map.from_struct() |> Map.keys()
  @intent_required MemoryIntent.__struct__() |> Map.from_struct() |> Map.keys()

  @spec grant(map()) :: {:ok, Grant.t()} | {:error, term()}
  def grant(attrs) when is_map(attrs) do
    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @grant_required -- [:operations]),
         :ok <- validate_operations(fetch(attrs, :operations)) do
      {:ok, struct!(Grant, take(attrs, @grant_required))}
    end
  end

  def grant(_attrs), do: {:error, :invalid_shared_memory_grant}

  @spec intent(map()) :: {:ok, MemoryIntent.t()} | {:error, term()}
  def intent(attrs) when is_map(attrs) do
    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @intent_required -- [:operation]),
         :ok <- validate_operation(fetch(attrs, :operation)) do
      {:ok, struct!(MemoryIntent, take(attrs, @intent_required))}
    end
  end

  def intent(_attrs), do: {:error, :invalid_shared_memory_intent}

  @spec authorize(map() | MemoryIntent.t(), [Grant.t() | map()], map()) ::
          {:ok, Decision.t()} | {:error, term()}
  def authorize(intent_attrs, grants, context \\ %{}) do
    with {:ok, memory_intent} <- normalize_intent(intent_attrs),
         {:ok, grant_set} <- normalize_grants(grants),
         :ok <- known_scope(memory_intent, context),
         :ok <- grant_allows(memory_intent, grant_set) do
      {:ok, decision(memory_intent)}
    end
  end

  @spec projection(Decision.t()) :: map()
  def projection(%Decision{} = decision) do
    %{
      decision_ref: decision.decision_ref,
      tenant_ref: decision.tenant_ref,
      installation_ref: decision.installation_ref,
      agent_ref: decision.agent_ref,
      memory_scope_ref: decision.memory_scope_ref,
      operation: decision.operation,
      memory_ref: decision.memory_ref,
      trace_ref: decision.trace_ref,
      decision: decision.decision,
      redaction_posture: decision.redaction_posture
    }
  end

  defp normalize_intent(%MemoryIntent{} = memory_intent), do: {:ok, memory_intent}
  defp normalize_intent(attrs), do: intent(attrs)

  defp normalize_grants(grants) when is_list(grants) do
    Enum.reduce_while(grants, {:ok, []}, fn grant_attrs, {:ok, acc} ->
      case normalize_grant(grant_attrs) do
        {:ok, grant} -> {:cont, {:ok, [grant | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_grants(_grants), do: {:error, :invalid_shared_memory_grants}

  defp normalize_grant(%Grant{} = grant), do: {:ok, grant}
  defp normalize_grant(attrs), do: grant(attrs)

  defp known_scope(intent, context) do
    known_scopes = fetch(context, :known_memory_scope_refs) || []

    if intent.memory_scope_ref in known_scopes do
      :ok
    else
      {:error, :unknown_memory_scope}
    end
  end

  defp grant_allows(intent, grants) do
    Enum.find_value(grants, {:error, :missing_shared_memory_grant}, fn grant ->
      if grant_matches?(intent, grant) do
        :ok
      end
    end)
  end

  defp grant_matches?(intent, grant) do
    intent.tenant_ref == grant.tenant_ref and
      intent.installation_ref == grant.installation_ref and
      intent.agent_ref == grant.agent_ref and
      intent.memory_scope_ref == grant.memory_scope_ref and
      intent.operation in grant.operations
  end

  defp decision(intent) do
    %Decision{
      decision_ref: "shared-memory-decision://" <> intent.intent_ref,
      tenant_ref: intent.tenant_ref,
      installation_ref: intent.installation_ref,
      agent_ref: intent.agent_ref,
      memory_scope_ref: intent.memory_scope_ref,
      operation: intent.operation,
      memory_ref: intent.memory_ref,
      trace_ref: intent.trace_ref,
      decision: :allow,
      redaction_posture: intent.redaction_posture
    }
  end

  defp validate_operations(operations) when is_list(operations) and operations != [] do
    if Enum.all?(operations, &(&1 in @operations)) do
      :ok
    else
      {:error, :unknown_shared_memory_operation}
    end
  end

  defp validate_operations(_operations), do: {:error, :missing_shared_memory_operations}

  defp validate_operation(operation) do
    if operation in @operations do
      :ok
    else
      {:error, :unknown_shared_memory_operation}
    end
  end

  defp required_strings(attrs, keys) do
    Enum.reduce_while(keys, :ok, fn key, :ok ->
      case fetch(attrs, key) do
        value when is_binary(value) and value != "" -> {:cont, :ok}
        _other -> {:halt, {:error, {:missing_ref, key}}}
      end
    end)
  end

  defp take(attrs, keys), do: Map.new(keys, fn key -> {key, fetch!(attrs, key)} end)

  defp fetch!(attrs, key), do: fetch(attrs, key)

  defp fetch(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp reject_raw(value), do: reject_raw(value, [])

  defp reject_raw(%_struct{} = value, path), do: value |> Map.from_struct() |> reject_raw(path)

  defp reject_raw(%{} = map, path) do
    Enum.reduce_while(map, :ok, fn {key, value}, :ok ->
      reject_raw_entry(key, value, path)
    end)
  end

  defp reject_raw(list, path) when is_list(list) do
    Enum.reduce_while(list, :ok, fn value, :ok ->
      case reject_raw(value, path) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reject_raw(_value, _path), do: :ok

  defp reject_raw_entry(key, value, path) do
    if key in @raw_keys do
      {:halt, {:error, {:raw_field_rejected, Enum.reverse([key | path])}}}
    else
      reject_nested_raw(key, value, path)
    end
  end

  defp reject_nested_raw(key, value, path) do
    case reject_raw(value, [key | path]) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end
end
