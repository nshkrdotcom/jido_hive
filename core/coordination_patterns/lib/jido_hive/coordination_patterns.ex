defmodule JidoHive.CoordinationPatterns do
  @moduledoc """
  Bounded coordination pattern contracts.
  """

  defmodule PatternSpec do
    @moduledoc "Ref-only coordination pattern specification."
    @enforce_keys [
      :pattern_ref,
      :pattern_name,
      :tenant_ref,
      :installation_ref,
      :authority_ref,
      :budget_profile_ref,
      :trace_ref,
      :max_agents,
      :max_turns,
      :max_messages,
      :max_tokens,
      :cancellation_policy_ref,
      :memory_policy_ref,
      :replay_policy,
      :connector_policy_ref,
      :approved_connector_refs,
      :redaction_posture
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  defmodule PatternProjection do
    @moduledoc "Operator-safe pattern projection."
    @enforce_keys [
      :pattern_ref,
      :pattern_name,
      :tenant_ref,
      :installation_ref,
      :budget_profile_ref,
      :trace_ref,
      :max_agents,
      :max_turns,
      :max_messages,
      :max_tokens,
      :replay_policy,
      :redaction_posture
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  @pattern_names [:orchestrator_worker, :debate, :consensus, :hierarchical_decomposition]
  @replay_policies [:suppress_provider_effects, :simulation_only]
  @positive_integer_keys [:max_agents, :max_turns, :max_messages, :max_tokens]
  @required PatternSpec.__struct__() |> Map.from_struct() |> Map.keys()
  @non_string_keys [:pattern_name, :replay_policy, :approved_connector_refs] ++
                     @positive_integer_keys
  @string_required_keys @required -- @non_string_keys
  @raw_keys [
    :agent_message_body,
    :body,
    :memory_body,
    :payload,
    :private_state,
    :prompt_body,
    :provider_payload,
    :raw_body,
    :secret,
    "agent_message_body",
    "body",
    "memory_body",
    "payload",
    "private_state",
    "prompt_body",
    "provider_payload",
    "raw_body",
    "secret"
  ]

  @spec spec(map()) :: {:ok, PatternSpec.t()} | {:error, term()}
  def spec(attrs) when is_map(attrs) do
    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @string_required_keys),
         :ok <- required_positive_integers(attrs, @positive_integer_keys),
         :ok <- validate_pattern(fetch(attrs, :pattern_name)),
         :ok <- validate_replay(fetch(attrs, :replay_policy)),
         :ok <- validate_connectors(fetch(attrs, :approved_connector_refs)),
         :ok <- reject_cross_tenant(attrs) do
      {:ok, struct!(PatternSpec, take(attrs, @required))}
    end
  end

  def spec(_attrs), do: {:error, :invalid_coordination_pattern}

  @spec projection(PatternSpec.t()) :: PatternProjection.t()
  def projection(%PatternSpec{} = spec) do
    %PatternProjection{
      pattern_ref: spec.pattern_ref,
      pattern_name: spec.pattern_name,
      tenant_ref: spec.tenant_ref,
      installation_ref: spec.installation_ref,
      budget_profile_ref: spec.budget_profile_ref,
      trace_ref: spec.trace_ref,
      max_agents: spec.max_agents,
      max_turns: spec.max_turns,
      max_messages: spec.max_messages,
      max_tokens: spec.max_tokens,
      replay_policy: spec.replay_policy,
      redaction_posture: spec.redaction_posture
    }
  end

  @spec plan(map()) :: {:ok, map()} | {:error, term()}
  def plan(attrs) do
    with {:ok, pattern} <- spec(attrs) do
      {:ok,
       %{
         pattern_ref: pattern.pattern_ref,
         pattern_name: pattern.pattern_name,
         bounds_ref: "coordination-bounds://" <> pattern.pattern_ref,
         budget_profile_ref: pattern.budget_profile_ref,
         replay_policy: pattern.replay_policy,
         provider_effect_status: :suppressed_for_replay,
         redaction_posture: pattern.redaction_posture
       }}
    end
  end

  defp validate_pattern(pattern_name) do
    if pattern_name in @pattern_names do
      :ok
    else
      {:error, :unknown_coordination_pattern}
    end
  end

  defp validate_replay(replay_policy) do
    if replay_policy in @replay_policies do
      :ok
    else
      {:error, :side_effecting_replay_not_allowed}
    end
  end

  defp validate_connectors(connectors) when is_list(connectors) and connectors != [], do: :ok
  defp validate_connectors(_connectors), do: {:error, :unapproved_connector_use}

  defp reject_cross_tenant(attrs) do
    handoff_tenant = fetch(attrs, :handoff_tenant_ref) || fetch(attrs, :tenant_ref)

    if handoff_tenant == fetch(attrs, :tenant_ref) do
      :ok
    else
      {:error, :implicit_cross_tenant_handoff}
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

  defp required_positive_integers(attrs, keys) do
    Enum.reduce_while(keys, :ok, fn key, :ok ->
      case fetch(attrs, key) do
        value when is_integer(value) and value > 0 -> {:cont, :ok}
        _other -> {:halt, {:error, {:invalid_bound, key}}}
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
