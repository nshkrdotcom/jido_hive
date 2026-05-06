defmodule JidoHive.AgentCoordinator do
  @moduledoc """
  Workflow-scoped spawn, handoff, cancel, and supervise contracts.
  """

  defmodule Store do
    @moduledoc "Coordination store posture."
    @enforce_keys [:mode, :adapter_ref, :preflight_ref]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            mode: :memory | :durable,
            adapter_ref: String.t(),
            preflight_ref: String.t()
          }
  end

  defmodule SpawnIntent do
    @moduledoc "Governed spawn intent."
    @enforce_keys [
      :agent_ref,
      :tenant_ref,
      :authority_ref,
      :installation_ref,
      :idempotency_key,
      :trace_ref,
      :persistence_ref,
      :workflow_lifecycle_ref,
      :parent_workflow_ref,
      :skill_ref,
      :skill_admission_ref,
      :memory_scope_ref,
      :budget_ref,
      :guard_chain_ref,
      :target_ref,
      :release_manifest_ref
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  defmodule HandoffIntent do
    @moduledoc "Governed handoff intent."
    @enforce_keys [
      :handoff_ref,
      :from_agent_ref,
      :to_agent_ref,
      :tenant_ref,
      :authority_ref,
      :installation_ref,
      :idempotency_key,
      :trace_ref,
      :persistence_ref,
      :memory_scope_ref,
      :budget_ref,
      :workflow_lifecycle_ref,
      :release_manifest_ref
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  defmodule CoordinationRecord do
    @moduledoc "Effect-free coordination record."
    @enforce_keys [
      :record_ref,
      :agent_ref,
      :tenant_ref,
      :installation_ref,
      :workflow_lifecycle_ref,
      :budget_ref,
      :memory_scope_ref,
      :trace_ref,
      :store_mode,
      :effect_status,
      :redaction_posture
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  @raw_keys [
    :agent_message_body,
    :authorization,
    :authorization_header,
    :body,
    :credential,
    :memory_body,
    :private_state,
    :prompt_body,
    :provider_payload,
    :raw_body,
    :secret,
    :token,
    "agent_message_body",
    "authorization",
    "authorization_header",
    "body",
    "credential",
    "memory_body",
    "private_state",
    "prompt_body",
    "provider_payload",
    "raw_body",
    "secret",
    "token"
  ]

  @spawn_required SpawnIntent.__struct__() |> Map.from_struct() |> Map.keys()
  @handoff_required HandoffIntent.__struct__() |> Map.from_struct() |> Map.keys()

  @spec memory_store() :: Store.t()
  def memory_store do
    %Store{
      mode: :memory,
      adapter_ref: "memory://jido-hive/agent-coordinator",
      preflight_ref: "preflight://memory/default"
    }
  end

  @spec store(map() | keyword()) :: {:ok, Store.t()} | {:error, term()}
  def store(attrs \\ %{})
  def store(%{} = attrs) when map_size(attrs) == 0, do: {:ok, memory_store()}
  def store([]), do: {:ok, memory_store()}

  def store(attrs) when is_map(attrs) do
    with :ok <- reject_raw(attrs),
         :durable <- fetch(attrs, :mode),
         :ok <- required_strings(attrs, [:adapter_ref, :preflight_ref]) do
      {:ok,
       %Store{
         mode: :durable,
         adapter_ref: fetch!(attrs, :adapter_ref),
         preflight_ref: fetch!(attrs, :preflight_ref)
       }}
    else
      :memory -> {:ok, memory_store()}
      nil -> {:ok, memory_store()}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_store_mode}
    end
  end

  def store(_attrs), do: {:error, :invalid_store_config}

  @spec spawn_intent(map()) :: {:ok, SpawnIntent.t()} | {:error, term()}
  def spawn_intent(attrs) when is_map(attrs) do
    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @spawn_required) do
      {:ok, struct!(SpawnIntent, take(attrs, @spawn_required))}
    end
  end

  def spawn_intent(_attrs), do: {:error, :invalid_spawn_intent}

  @spec spawn_agent(map(), map() | Store.t()) :: {:ok, CoordinationRecord.t()} | {:error, term()}
  def spawn_agent(attrs, store_attrs \\ %{}) do
    with {:ok, intent} <- spawn_intent(attrs),
         {:ok, store} <- normalize_store(store_attrs) do
      {:ok,
       %CoordinationRecord{
         record_ref: "coordination://" <> intent.agent_ref,
         agent_ref: intent.agent_ref,
         tenant_ref: intent.tenant_ref,
         installation_ref: intent.installation_ref,
         workflow_lifecycle_ref: intent.workflow_lifecycle_ref,
         budget_ref: intent.budget_ref,
         memory_scope_ref: intent.memory_scope_ref,
         trace_ref: intent.trace_ref,
         store_mode: store.mode,
         effect_status: :coordination_recorded_no_provider_effect,
         redaction_posture: "refs_only"
       }}
    end
  end

  @spec handoff_intent(map()) :: {:ok, HandoffIntent.t()} | {:error, term()}
  def handoff_intent(attrs) when is_map(attrs) do
    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @handoff_required),
         :ok <- same_scope(attrs) do
      {:ok, struct!(HandoffIntent, take(attrs, @handoff_required))}
    end
  end

  def handoff_intent(_attrs), do: {:error, :invalid_handoff_intent}

  @spec handoff(map()) :: {:ok, map()} | {:error, term()}
  def handoff(attrs) do
    with {:ok, intent} <- handoff_intent(attrs) do
      {:ok,
       %{
         handoff_ref: intent.handoff_ref,
         from_agent_ref: intent.from_agent_ref,
         to_agent_ref: intent.to_agent_ref,
         tenant_ref: intent.tenant_ref,
         authority_ref: intent.authority_ref,
         installation_ref: intent.installation_ref,
         memory_scope_ref: intent.memory_scope_ref,
         budget_ref: intent.budget_ref,
         persistence_ref: intent.persistence_ref,
         trace_ref: intent.trace_ref,
         redaction_posture: "refs_only"
       }}
    end
  end

  @spec cancel(map()) :: {:ok, map()} | {:error, term()}
  def cancel(attrs) when is_map(attrs) do
    required = [:agent_ref, :tenant_ref, :authority_ref, :workflow_lifecycle_ref, :trace_ref]

    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, required) do
      {:ok,
       %{
         agent_ref: fetch!(attrs, :agent_ref),
         tenant_ref: fetch!(attrs, :tenant_ref),
         workflow_lifecycle_ref: fetch!(attrs, :workflow_lifecycle_ref),
         trace_ref: fetch!(attrs, :trace_ref),
         cancellation_status: :cancel_requested,
         redaction_posture: "refs_only"
       }}
    end
  end

  def cancel(_attrs), do: {:error, :invalid_cancel_intent}

  @spec supervise(map()) :: {:ok, map()} | {:error, term()}
  def supervise(attrs) when is_map(attrs) do
    required = [
      :supervision_ref,
      :tenant_ref,
      :authority_ref,
      :workflow_lifecycle_ref,
      :trace_ref
    ]

    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, required),
         :ok <- require_non_empty_list(attrs, :agent_refs) do
      {:ok,
       %{
         supervision_ref: fetch!(attrs, :supervision_ref),
         tenant_ref: fetch!(attrs, :tenant_ref),
         workflow_lifecycle_ref: fetch!(attrs, :workflow_lifecycle_ref),
         agent_refs: fetch!(attrs, :agent_refs),
         trace_ref: fetch!(attrs, :trace_ref),
         supervision_status: :bounded
       }}
    end
  end

  def supervise(_attrs), do: {:error, :invalid_supervision_plan}

  @spec trace_projection(CoordinationRecord.t()) :: map()
  def trace_projection(%CoordinationRecord{} = record) do
    %{
      trace_ref: record.trace_ref,
      agent_ref: record.agent_ref,
      tenant_ref: record.tenant_ref,
      installation_ref: record.installation_ref,
      workflow_lifecycle_ref: record.workflow_lifecycle_ref,
      memory_scope_ref: record.memory_scope_ref,
      budget_ref: record.budget_ref,
      redaction_posture: record.redaction_posture
    }
  end

  defp normalize_store(%Store{} = store), do: {:ok, store}
  defp normalize_store(attrs), do: store(attrs)

  defp same_scope(attrs) do
    if fetch(attrs, :from_agent_ref) == fetch(attrs, :to_agent_ref) do
      {:error, :self_handoff_not_allowed}
    else
      :ok
    end
  end

  defp require_non_empty_list(attrs, key) do
    case fetch(attrs, key) do
      values when is_list(values) and values != [] -> :ok
      _other -> {:error, {:missing_or_empty, key}}
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
