defmodule JidoHive.InterAgentMessaging do
  @moduledoc """
  Bounded inter-agent message contracts.
  """

  defmodule MessageIntent do
    @moduledoc "Ref-only inter-agent message intent."
    @enforce_keys [
      :message_ref,
      :sender_agent_ref,
      :recipient_agent_ref,
      :tenant_ref,
      :installation_ref,
      :authority_ref,
      :memory_scope_ref,
      :context_budget_ref,
      :budget_decision_ref,
      :idempotency_key,
      :trace_ref,
      :message_body_ref,
      :redaction_posture,
      :token_budget,
      :byte_budget,
      :turn_budget,
      :wall_clock_budget_ms,
      :max_fanout
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  defmodule RoutedMessage do
    @moduledoc "Effect-free routed message record."
    @enforce_keys [
      :message_ref,
      :sender_agent_ref,
      :recipient_agent_ref,
      :tenant_ref,
      :installation_ref,
      :context_budget_ref,
      :trace_ref,
      :delivery_status,
      :redaction_posture
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  @raw_keys [
    :agent_message_body,
    :body,
    :memory_body,
    :message_body,
    :payload,
    :private_state,
    :prompt_body,
    :provider_payload,
    :raw_body,
    :raw_message,
    :secret,
    :tool_output,
    "agent_message_body",
    "body",
    "memory_body",
    "message_body",
    "payload",
    "private_state",
    "prompt_body",
    "provider_payload",
    "raw_body",
    "raw_message",
    "secret",
    "tool_output"
  ]

  @intent_required MessageIntent.__struct__() |> Map.from_struct() |> Map.keys()
  @positive_integer_keys [
    :token_budget,
    :byte_budget,
    :turn_budget,
    :wall_clock_budget_ms,
    :max_fanout
  ]

  @spec message_intent(map()) :: {:ok, MessageIntent.t()} | {:error, term()}
  def message_intent(attrs) when is_map(attrs) do
    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @intent_required -- @positive_integer_keys),
         :ok <- required_positive_integers(attrs, @positive_integer_keys),
         :ok <- bounded_consumption(attrs),
         :ok <- same_tenant(attrs) do
      {:ok, struct!(MessageIntent, take(attrs, @intent_required))}
    end
  end

  def message_intent(_attrs), do: {:error, :invalid_message_intent}

  @spec route(map(), map()) :: {:ok, RoutedMessage.t()} | {:error, term()}
  def route(attrs, routing_context \\ %{}) do
    with {:ok, intent} <- message_intent(attrs),
         :ok <- declared_recipient(intent, routing_context),
         :ok <- bounded_fanout(intent, routing_context) do
      {:ok,
       %RoutedMessage{
         message_ref: intent.message_ref,
         sender_agent_ref: intent.sender_agent_ref,
         recipient_agent_ref: intent.recipient_agent_ref,
         tenant_ref: intent.tenant_ref,
         installation_ref: intent.installation_ref,
         context_budget_ref: intent.context_budget_ref,
         trace_ref: intent.trace_ref,
         delivery_status: :accepted_no_provider_effect,
         redaction_posture: intent.redaction_posture
       }}
    end
  end

  @spec projection(RoutedMessage.t()) :: map()
  def projection(%RoutedMessage{} = message) do
    %{
      message_ref: message.message_ref,
      sender_agent_ref: message.sender_agent_ref,
      recipient_agent_ref: message.recipient_agent_ref,
      tenant_ref: message.tenant_ref,
      installation_ref: message.installation_ref,
      context_budget_ref: message.context_budget_ref,
      trace_ref: message.trace_ref,
      delivery_status: message.delivery_status,
      redaction_posture: message.redaction_posture
    }
  end

  defp declared_recipient(intent, context) do
    declared = fetch(context, :declared_recipient_refs) || []

    if intent.recipient_agent_ref in declared do
      :ok
    else
      {:error, :undeclared_recipient}
    end
  end

  defp bounded_fanout(intent, context) do
    fanout_count = fetch(context, :fanout_count) || 1

    if is_integer(fanout_count) and fanout_count <= intent.max_fanout do
      :ok
    else
      {:error, :unbounded_fanout}
    end
  end

  defp bounded_consumption(attrs) do
    checks = [
      {:consumed_tokens, :token_budget},
      {:consumed_bytes, :byte_budget},
      {:consumed_turns, :turn_budget},
      {:elapsed_ms, :wall_clock_budget_ms}
    ]

    Enum.reduce_while(checks, :ok, fn {used_key, budget_key}, :ok ->
      used = fetch(attrs, used_key) || 0
      budget = fetch(attrs, budget_key)
      check_budget(used_key, used, budget)
    end)
  end

  defp check_budget(_key, used, budget) when is_integer(used) and used <= budget,
    do: {:cont, :ok}

  defp check_budget(key, _used, _budget), do: {:halt, {:error, {:budget_exhausted, key}}}

  defp same_tenant(attrs) do
    sender_tenant = fetch(attrs, :sender_tenant_ref) || fetch(attrs, :tenant_ref)
    recipient_tenant = fetch(attrs, :recipient_tenant_ref) || fetch(attrs, :tenant_ref)

    sender_installation =
      fetch(attrs, :sender_installation_ref) || fetch(attrs, :installation_ref)

    recipient_installation =
      fetch(attrs, :recipient_installation_ref) || fetch(attrs, :installation_ref)

    validate_scope(sender_tenant, recipient_tenant, sender_installation, recipient_installation)
  end

  defp validate_scope(tenant, tenant, installation, installation), do: :ok

  defp validate_scope(_sender_tenant, _recipient_tenant, installation, installation),
    do: {:error, :cross_tenant_message}

  defp validate_scope(
         _sender_tenant,
         _recipient_tenant,
         _sender_installation,
         _recipient_installation
       ),
       do: {:error, :cross_installation_message}

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
        _other -> {:halt, {:error, {:invalid_budget, key}}}
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
