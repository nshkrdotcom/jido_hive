defmodule JidoHive.SkillContracts do
  @moduledoc """
  Ref-only skill manifest and invocation contracts.
  """

  defmodule Skill do
    @moduledoc "Behaviour implemented by publishable skill bundles."

    @callback skill_manifest() :: map() | JidoHive.SkillContracts.SkillManifest.t()
  end

  defmodule SkillVersionRef do
    @moduledoc "Forward-only skill version reference."
    @enforce_keys [:skill_ref, :version_ref, :revision, :release_manifest_ref]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            skill_ref: String.t(),
            version_ref: String.t(),
            revision: pos_integer(),
            release_manifest_ref: String.t()
          }
  end

  defmodule SkillCapabilityBinding do
    @moduledoc "Declared connector capability binding for a skill."
    @enforce_keys [
      :binding_ref,
      :capability_ref,
      :connector_ref,
      :capability_id,
      :tenant_ref,
      :scope_ref,
      :contract_version
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            binding_ref: String.t(),
            capability_ref: String.t(),
            connector_ref: String.t(),
            capability_id: String.t(),
            tenant_ref: String.t(),
            scope_ref: String.t(),
            contract_version: String.t()
          }
  end

  defmodule SkillCompositionRef do
    @moduledoc "Declared skill composition edge."
    @enforce_keys [
      :composition_ref,
      :parent_skill_ref,
      :child_skill_ref,
      :tenant_ref,
      :memory_share_ref,
      :budget_profile_ref,
      :max_depth
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            composition_ref: String.t(),
            parent_skill_ref: String.t(),
            child_skill_ref: String.t(),
            tenant_ref: String.t(),
            memory_share_ref: String.t(),
            budget_profile_ref: String.t(),
            max_depth: pos_integer()
          }
  end

  defmodule SkillManifest do
    @moduledoc "Ref-only skill manifest."
    @enforce_keys [
      :skill_ref,
      :version_ref,
      :tenant_ref,
      :authority_ref,
      :installation_ref,
      :idempotency_key,
      :trace_ref,
      :persistence_profile_ref,
      :release_manifest_ref,
      :prompt_ref,
      :tool_refs,
      :memory_profile_ref,
      :guard_policy_ref,
      :eval_suite_ref,
      :budget_profile_ref,
      :conformance_ref,
      :capability_bindings
    ]
    defstruct [:composition_refs | @enforce_keys]

    @type t :: %__MODULE__{
            skill_ref: String.t(),
            version_ref: SkillVersionRef.t(),
            tenant_ref: String.t(),
            authority_ref: String.t(),
            installation_ref: String.t(),
            idempotency_key: String.t(),
            trace_ref: String.t(),
            persistence_profile_ref: String.t(),
            release_manifest_ref: String.t(),
            prompt_ref: String.t(),
            tool_refs: [String.t()],
            memory_profile_ref: String.t(),
            guard_policy_ref: String.t(),
            eval_suite_ref: String.t(),
            budget_profile_ref: String.t(),
            conformance_ref: String.t(),
            capability_bindings: [SkillCapabilityBinding.t()],
            composition_refs: [SkillCompositionRef.t()]
          }
  end

  defmodule SkillInvocationIntent do
    @moduledoc "Invocation intent that must pass all gates before provider effects."
    @enforce_keys [
      :invocation_ref,
      :skill_ref,
      :tenant_ref,
      :authority_ref,
      :installation_ref,
      :lease_ref,
      :target_ref,
      :prompt_ref,
      :memory_profile_ref,
      :guard_policy_ref,
      :eval_suite_ref,
      :budget_profile_ref,
      :connector_capability_refs,
      :trace_ref,
      :idempotency_key,
      :release_manifest_ref
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            invocation_ref: String.t(),
            skill_ref: String.t(),
            tenant_ref: String.t(),
            authority_ref: String.t(),
            installation_ref: String.t(),
            lease_ref: String.t(),
            target_ref: String.t(),
            prompt_ref: String.t(),
            memory_profile_ref: String.t(),
            guard_policy_ref: String.t(),
            eval_suite_ref: String.t(),
            budget_profile_ref: String.t(),
            connector_capability_refs: [String.t()],
            trace_ref: String.t(),
            idempotency_key: String.t(),
            release_manifest_ref: String.t()
          }
  end

  @manifest_string_fields [
    :skill_ref,
    :tenant_ref,
    :authority_ref,
    :installation_ref,
    :idempotency_key,
    :trace_ref,
    :persistence_profile_ref,
    :release_manifest_ref,
    :prompt_ref,
    :memory_profile_ref,
    :guard_policy_ref,
    :eval_suite_ref,
    :budget_profile_ref,
    :conformance_ref
  ]
  @binding_fields [
    :binding_ref,
    :capability_ref,
    :connector_ref,
    :capability_id,
    :tenant_ref,
    :scope_ref,
    :contract_version
  ]
  @composition_string_fields [
    :composition_ref,
    :parent_skill_ref,
    :child_skill_ref,
    :tenant_ref,
    :memory_share_ref,
    :budget_profile_ref
  ]
  @version_string_fields [:skill_ref, :version_ref, :release_manifest_ref]
  @intent_string_fields [
    :invocation_ref,
    :skill_ref,
    :tenant_ref,
    :authority_ref,
    :installation_ref,
    :lease_ref,
    :target_ref,
    :prompt_ref,
    :memory_profile_ref,
    :guard_policy_ref,
    :eval_suite_ref,
    :budget_profile_ref,
    :trace_ref,
    :idempotency_key,
    :release_manifest_ref
  ]
  @raw_keys [
    :authorization,
    :authorization_header,
    :body,
    :content,
    :credential,
    :credentials,
    :memory_body,
    :private_state,
    :private_state_body,
    :prompt_body,
    :provider_account_id,
    :provider_payload,
    :raw_authorization,
    :raw_body,
    :raw_content,
    :raw_memory,
    :raw_private_state,
    :raw_prompt,
    :raw_secret,
    :raw_token,
    :secret,
    :token,
    "authorization",
    "authorization_header",
    "body",
    "content",
    "credential",
    "credentials",
    "memory_body",
    "private_state",
    "private_state_body",
    "prompt_body",
    "provider_account_id",
    "provider_payload",
    "raw_authorization",
    "raw_body",
    "raw_content",
    "raw_memory",
    "raw_private_state",
    "raw_prompt",
    "raw_secret",
    "raw_token",
    "secret",
    "token"
  ]

  @spec manifest(map() | keyword() | SkillManifest.t()) ::
          {:ok, SkillManifest.t()} | {:error, term()}
  def manifest(%SkillManifest{} = manifest), do: validate_manifest(manifest)

  def manifest(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = to_map(attrs)

    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @manifest_string_fields),
         {:ok, version_ref} <- attrs |> fetch(:version_ref) |> version_ref(),
         :ok <- version_matches_skill(version_ref, fetch!(attrs, :skill_ref)),
         {:ok, tool_refs} <- non_empty_string_list(attrs, :tool_refs),
         {:ok, capability_bindings} <- capability_bindings(fetch(attrs, :capability_bindings)),
         {:ok, composition_refs} <- composition_refs(fetch(attrs, :composition_refs, [])) do
      validate_manifest(%SkillManifest{
        skill_ref: fetch!(attrs, :skill_ref),
        version_ref: version_ref,
        tenant_ref: fetch!(attrs, :tenant_ref),
        authority_ref: fetch!(attrs, :authority_ref),
        installation_ref: fetch!(attrs, :installation_ref),
        idempotency_key: fetch!(attrs, :idempotency_key),
        trace_ref: fetch!(attrs, :trace_ref),
        persistence_profile_ref: fetch!(attrs, :persistence_profile_ref),
        release_manifest_ref: fetch!(attrs, :release_manifest_ref),
        prompt_ref: fetch!(attrs, :prompt_ref),
        tool_refs: tool_refs,
        memory_profile_ref: fetch!(attrs, :memory_profile_ref),
        guard_policy_ref: fetch!(attrs, :guard_policy_ref),
        eval_suite_ref: fetch!(attrs, :eval_suite_ref),
        budget_profile_ref: fetch!(attrs, :budget_profile_ref),
        conformance_ref: fetch!(attrs, :conformance_ref),
        capability_bindings: capability_bindings,
        composition_refs: composition_refs
      })
    end
  end

  def manifest(_attrs), do: {:error, :invalid_skill_manifest}

  @spec manifest!(map() | keyword() | SkillManifest.t()) :: SkillManifest.t()
  def manifest!(attrs) do
    case manifest(attrs) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid skill manifest: #{inspect(reason)}"
    end
  end

  @spec version_ref(map() | keyword() | SkillVersionRef.t()) ::
          {:ok, SkillVersionRef.t()} | {:error, term()}
  def version_ref(%SkillVersionRef{} = version_ref) do
    with :ok <- validate_version_ref(version_ref) do
      {:ok, version_ref}
    end
  end

  def version_ref(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = to_map(attrs)

    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @version_string_fields),
         {:ok, revision} <- positive_integer(attrs, :revision) do
      version_ref = %SkillVersionRef{
        skill_ref: fetch!(attrs, :skill_ref),
        version_ref: fetch!(attrs, :version_ref),
        revision: revision,
        release_manifest_ref: fetch!(attrs, :release_manifest_ref)
      }

      with :ok <- validate_version_ref(version_ref) do
        {:ok, version_ref}
      end
    end
  end

  def version_ref(_attrs), do: {:error, :invalid_skill_version_ref}

  @spec capability_binding(map() | keyword() | SkillCapabilityBinding.t()) ::
          {:ok, SkillCapabilityBinding.t()} | {:error, term()}
  def capability_binding(%SkillCapabilityBinding{} = binding), do: validate_binding(binding)

  def capability_binding(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = to_map(attrs)

    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @binding_fields) do
      validate_binding(%SkillCapabilityBinding{
        binding_ref: fetch!(attrs, :binding_ref),
        capability_ref: fetch!(attrs, :capability_ref),
        connector_ref: fetch!(attrs, :connector_ref),
        capability_id: fetch!(attrs, :capability_id),
        tenant_ref: fetch!(attrs, :tenant_ref),
        scope_ref: fetch!(attrs, :scope_ref),
        contract_version: fetch!(attrs, :contract_version)
      })
    end
  end

  def capability_binding(_attrs), do: {:error, :invalid_skill_capability_binding}

  @spec composition_ref(map() | keyword() | SkillCompositionRef.t()) ::
          {:ok, SkillCompositionRef.t()} | {:error, term()}
  def composition_ref(%SkillCompositionRef{} = composition_ref),
    do: validate_composition_ref(composition_ref)

  def composition_ref(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = to_map(attrs)

    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @composition_string_fields),
         {:ok, max_depth} <- positive_integer(attrs, :max_depth) do
      validate_composition_ref(%SkillCompositionRef{
        composition_ref: fetch!(attrs, :composition_ref),
        parent_skill_ref: fetch!(attrs, :parent_skill_ref),
        child_skill_ref: fetch!(attrs, :child_skill_ref),
        tenant_ref: fetch!(attrs, :tenant_ref),
        memory_share_ref: fetch!(attrs, :memory_share_ref),
        budget_profile_ref: fetch!(attrs, :budget_profile_ref),
        max_depth: max_depth
      })
    end
  end

  def composition_ref(_attrs), do: {:error, :invalid_skill_composition_ref}

  @spec invocation_intent(map() | keyword() | SkillInvocationIntent.t()) ::
          {:ok, SkillInvocationIntent.t()} | {:error, term()}
  def invocation_intent(%SkillInvocationIntent{} = intent), do: validate_intent(intent)

  def invocation_intent(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = to_map(attrs)

    with :ok <- reject_raw(attrs),
         :ok <- required_strings(attrs, @intent_string_fields),
         {:ok, connector_capability_refs} <-
           non_empty_string_list(attrs, :connector_capability_refs) do
      validate_intent(%SkillInvocationIntent{
        invocation_ref: fetch!(attrs, :invocation_ref),
        skill_ref: fetch!(attrs, :skill_ref),
        tenant_ref: fetch!(attrs, :tenant_ref),
        authority_ref: fetch!(attrs, :authority_ref),
        installation_ref: fetch!(attrs, :installation_ref),
        lease_ref: fetch!(attrs, :lease_ref),
        target_ref: fetch!(attrs, :target_ref),
        prompt_ref: fetch!(attrs, :prompt_ref),
        memory_profile_ref: fetch!(attrs, :memory_profile_ref),
        guard_policy_ref: fetch!(attrs, :guard_policy_ref),
        eval_suite_ref: fetch!(attrs, :eval_suite_ref),
        budget_profile_ref: fetch!(attrs, :budget_profile_ref),
        connector_capability_refs: connector_capability_refs,
        trace_ref: fetch!(attrs, :trace_ref),
        idempotency_key: fetch!(attrs, :idempotency_key),
        release_manifest_ref: fetch!(attrs, :release_manifest_ref)
      })
    end
  end

  def invocation_intent(_attrs), do: {:error, :invalid_skill_invocation_intent}

  @spec invocation_intent!(map() | keyword() | SkillInvocationIntent.t()) ::
          SkillInvocationIntent.t()
  def invocation_intent!(attrs) do
    case invocation_intent(attrs) do
      {:ok, value} ->
        value

      {:error, reason} ->
        raise ArgumentError, "invalid skill invocation intent: #{inspect(reason)}"
    end
  end

  @spec projection(SkillManifest.t()) :: map()
  def projection(%SkillManifest{} = manifest) do
    %{
      skill_ref: manifest.skill_ref,
      version_ref: manifest.version_ref.version_ref,
      revision: manifest.version_ref.revision,
      tenant_ref: manifest.tenant_ref,
      installation_ref: manifest.installation_ref,
      prompt_ref: manifest.prompt_ref,
      tool_refs: manifest.tool_refs,
      memory_profile_ref: manifest.memory_profile_ref,
      guard_policy_ref: manifest.guard_policy_ref,
      eval_suite_ref: manifest.eval_suite_ref,
      budget_profile_ref: manifest.budget_profile_ref,
      conformance_ref: manifest.conformance_ref,
      capability_refs: Enum.map(manifest.capability_bindings, & &1.capability_ref),
      trace_ref: manifest.trace_ref,
      release_manifest_ref: manifest.release_manifest_ref,
      redaction_posture: "refs_only"
    }
  end

  @spec trace_projection(SkillManifest.t()) :: map()
  def trace_projection(%SkillManifest{} = manifest) do
    %{
      trace_ref: manifest.trace_ref,
      skill_ref: manifest.skill_ref,
      version_ref: manifest.version_ref.version_ref,
      prompt_ref: manifest.prompt_ref,
      guard_policy_ref: manifest.guard_policy_ref,
      eval_suite_ref: manifest.eval_suite_ref,
      budget_profile_ref: manifest.budget_profile_ref,
      capability_refs: Enum.map(manifest.capability_bindings, & &1.capability_ref),
      release_manifest_ref: manifest.release_manifest_ref,
      redaction_posture: "private_state_redacted"
    }
  end

  @spec reject_raw(term()) :: :ok | {:error, term()}
  def reject_raw(value), do: reject_raw(value, [])

  defp validate_manifest(%SkillManifest{} = manifest) do
    with :ok <- reject_raw(manifest),
         :ok <- required_struct_strings(manifest, @manifest_string_fields),
         :ok <- validate_version_ref(manifest.version_ref),
         :ok <- version_matches_skill(manifest.version_ref, manifest.skill_ref),
         :ok <- non_empty_strings(manifest.tool_refs, :tool_refs),
         :ok <- non_empty_bindings(manifest.capability_bindings),
         :ok <- unique_capability_bindings(manifest.capability_bindings),
         :ok <- validate_compositions(manifest.composition_refs || []) do
      {:ok, manifest}
    end
  end

  defp validate_version_ref(%SkillVersionRef{} = version_ref) do
    case reject_raw(version_ref) do
      :ok -> validate_version_ref_fields(version_ref)
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_version_ref_fields(%SkillVersionRef{} = version_ref) do
    case required_struct_strings(version_ref, @version_string_fields) do
      :ok -> positive(version_ref.revision, :revision)
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_binding(%SkillCapabilityBinding{} = binding) do
    with :ok <- reject_raw(binding),
         :ok <- required_struct_strings(binding, @binding_fields) do
      {:ok, binding}
    end
  end

  defp validate_composition_ref(%SkillCompositionRef{} = composition_ref) do
    with :ok <- reject_raw(composition_ref),
         :ok <- required_struct_strings(composition_ref, @composition_string_fields),
         :ok <- positive(composition_ref.max_depth, :max_depth) do
      {:ok, composition_ref}
    end
  end

  defp validate_intent(%SkillInvocationIntent{} = intent) do
    with :ok <- reject_raw(intent),
         :ok <- required_struct_strings(intent, @intent_string_fields),
         :ok <- non_empty_strings(intent.connector_capability_refs, :connector_capability_refs) do
      {:ok, intent}
    end
  end

  defp capability_bindings(bindings) when is_list(bindings) and bindings != [] do
    bindings
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, acc} ->
      case capability_binding(attrs) do
        {:ok, binding} -> {:cont, {:ok, [binding | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> values |> Enum.reverse() |> unique_capability_bindings_value()
      {:error, reason} -> {:error, reason}
    end
  end

  defp capability_bindings(_bindings), do: {:error, {:missing_skill_list, :capability_bindings}}

  defp composition_refs(refs) when is_list(refs) do
    Enum.reduce_while(refs, {:ok, []}, fn attrs, {:ok, acc} ->
      case composition_ref(attrs) do
        {:ok, composition} -> {:cont, {:ok, [composition | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp composition_refs(_refs), do: {:error, {:invalid_skill_list, :composition_refs}}

  defp validate_compositions(composition_refs) when is_list(composition_refs) do
    case Enum.find(composition_refs, &(not match?({:ok, _value}, validate_composition_ref(&1)))) do
      nil -> :ok
      _composition_ref -> {:error, :invalid_skill_composition_ref}
    end
  end

  defp unique_capability_bindings(bindings) do
    case unique_capability_bindings_value(bindings) do
      {:ok, _bindings} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp unique_capability_bindings_value(bindings) do
    identities = Enum.map(bindings, &binding_identity/1)

    if length(Enum.uniq(identities)) == length(identities) do
      {:ok, bindings}
    else
      {:error, :duplicate_skill_capability_binding}
    end
  end

  defp binding_identity(%SkillCapabilityBinding{} = binding) do
    {binding.connector_ref, binding.capability_id, binding.tenant_ref, binding.scope_ref}
  end

  defp non_empty_bindings(bindings) when is_list(bindings) and bindings != [], do: :ok
  defp non_empty_bindings(_bindings), do: {:error, {:missing_skill_list, :capability_bindings}}

  defp non_empty_string_list(attrs, field) do
    values = fetch(attrs, field)

    with :ok <- non_empty_strings(values, field) do
      {:ok, values}
    end
  end

  defp non_empty_strings(values, field) when is_list(values) and values != [] do
    if Enum.all?(values, &present_string?/1) do
      :ok
    else
      {:error, {:invalid_skill_ref_list, field}}
    end
  end

  defp non_empty_strings(_values, field), do: {:error, {:missing_skill_list, field}}

  defp required_strings(attrs, fields) do
    case Enum.find(fields, &(not present_string?(fetch(attrs, &1)))) do
      nil -> :ok
      field -> {:error, {:missing_skill_ref, field}}
    end
  end

  defp required_struct_strings(struct, fields) do
    case Enum.find(fields, &(not present_string?(Map.fetch!(struct, &1)))) do
      nil -> :ok
      field -> {:error, {:missing_skill_ref, field}}
    end
  end

  defp positive_integer(attrs, field) do
    case fetch(attrs, field) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _value -> {:error, {:invalid_skill_positive_integer, field}}
    end
  end

  defp positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp positive(_value, field), do: {:error, {:invalid_skill_positive_integer, field}}

  defp version_matches_skill(%SkillVersionRef{skill_ref: skill_ref}, skill_ref), do: :ok

  defp version_matches_skill(%SkillVersionRef{}, _skill_ref),
    do: {:error, :skill_version_ref_mismatch}

  defp reject_raw(value, path) when is_map(value) do
    value
    |> map_entries()
    |> Enum.reduce_while(:ok, fn {key, nested_value}, :ok ->
      reject_raw_map_entry(key, nested_value, path)
    end)
  end

  defp reject_raw(values, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case reject_raw(value, [index | path]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reject_raw(_value, _path), do: :ok

  defp reject_raw_map_entry(key, _nested_value, path) when key in @raw_keys do
    {:halt, {:error, {:raw_skill_field_forbidden, Enum.reverse([key | path])}}}
  end

  defp reject_raw_map_entry(key, nested_value, path) do
    reject_nested_raw(nested_value, [key | path])
  end

  defp reject_nested_raw(nested_value, path) do
    case reject_raw(nested_value, path) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp map_entries(%module{} = value) when is_atom(module) do
    value
    |> Map.from_struct()
    |> Map.to_list()
  end

  defp map_entries(value), do: Map.to_list(value)

  defp to_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp to_map(attrs) when is_map(attrs), do: attrs

  defp fetch!(attrs, field), do: fetch(attrs, field)
  defp fetch(attrs, field), do: fetch(attrs, field, nil)

  defp fetch(attrs, field, default) do
    cond do
      Map.has_key?(attrs, field) -> Map.fetch!(attrs, field)
      Map.has_key?(attrs, Atom.to_string(field)) -> Map.fetch!(attrs, Atom.to_string(field))
      true -> default
    end
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
end
