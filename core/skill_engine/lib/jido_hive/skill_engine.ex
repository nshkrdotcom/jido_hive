defmodule JidoHive.SkillEngine do
  @moduledoc """
  Memory-default skill admission, versioning, composition, and invocation gates.
  """

  alias JidoHive.SkillContracts
  alias JidoHive.SkillContracts.SkillCompositionRef
  alias JidoHive.SkillContracts.SkillInvocationIntent
  alias JidoHive.SkillContracts.SkillManifest
  alias JidoHive.SkillContracts.SkillVersionRef

  defmodule Store do
    @moduledoc "In-memory admission store."
    @enforce_keys [:persistence_mode, :admissions, :versions, :invocations, :compositions]
    defstruct [:durable_adapter_ref, :durable_preflight_ref | @enforce_keys]

    @type t :: %__MODULE__{
            persistence_mode: :memory | :durable,
            durable_adapter_ref: String.t() | nil,
            durable_preflight_ref: String.t() | nil,
            admissions: map(),
            versions: map(),
            invocations: [JidoHive.SkillEngine.InvocationRecord.t()],
            compositions: [JidoHive.SkillEngine.CompositionRecord.t()]
          }
  end

  defmodule AdmissionRecord do
    @moduledoc "Skill admission record."
    @enforce_keys [
      :admission_ref,
      :skill_ref,
      :tenant_ref,
      :manifest,
      :version_ref,
      :trace_ref,
      :release_manifest_ref,
      :persistence_mode,
      :status
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            admission_ref: String.t(),
            skill_ref: String.t(),
            tenant_ref: String.t(),
            manifest: SkillManifest.t(),
            version_ref: SkillVersionRef.t(),
            trace_ref: String.t(),
            release_manifest_ref: String.t(),
            persistence_mode: :memory | :durable,
            status: :admitted
          }
  end

  defmodule InvocationRecord do
    @moduledoc "Skill invocation record after all gates pass."
    @enforce_keys [
      :invocation_ref,
      :skill_ref,
      :tenant_ref,
      :trace_ref,
      :release_manifest_ref,
      :gate_refs,
      :effect_status,
      :provider_effect_started?
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            invocation_ref: String.t(),
            skill_ref: String.t(),
            tenant_ref: String.t(),
            trace_ref: String.t(),
            release_manifest_ref: String.t(),
            gate_refs: map(),
            effect_status: :ready_after_gates,
            provider_effect_started?: false
          }
  end

  defmodule CompositionRecord do
    @moduledoc "Accepted bounded skill composition."
    @enforce_keys [:composition_ref, :parent_skill_ref, :child_skill_ref, :tenant_ref]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            composition_ref: String.t(),
            parent_skill_ref: String.t(),
            child_skill_ref: String.t(),
            tenant_ref: String.t()
          }
  end

  @allow_guard_decisions [:allow, :allow_with_redaction, "allow", "allow_with_redaction"]
  @allow_budget_decisions [:allow, :allow_warn_soft, :allow_with_override, "allow"]

  @spec new_store(map() | keyword()) :: {:ok, Store.t()} | {:error, term()}
  def new_store(attrs \\ %{}) do
    attrs = to_map(attrs)

    case persistence_mode(fetch(attrs, :persistence, :memory)) do
      {:ok, :memory} ->
        {:ok, empty_store(:memory, nil, nil)}

      {:ok, :durable} ->
        with {:ok, adapter_ref} <- required_string(attrs, :durable_adapter_ref),
             {:ok, preflight_ref} <- required_string(attrs, :durable_preflight_ref) do
          {:ok, empty_store(:durable, adapter_ref, preflight_ref)}
        else
          {:error, reason} -> {:error, {:durable_skill_store_preflight_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec verification_refs_for(SkillManifest.t()) :: map()
  def verification_refs_for(%SkillManifest{} = manifest) do
    %{
      prompt_refs: [manifest.prompt_ref],
      guard_policy_refs: [manifest.guard_policy_ref],
      eval_suite_refs: [manifest.eval_suite_ref],
      memory_profile_refs: [manifest.memory_profile_ref],
      budget_profile_refs: [manifest.budget_profile_ref],
      connector_capability_refs: Enum.map(manifest.capability_bindings, & &1.capability_ref),
      conformance_status: :passed
    }
  end

  @spec invocation_gate_refs_for(SkillInvocationIntent.t()) :: map()
  def invocation_gate_refs_for(%SkillInvocationIntent{} = intent) do
    %{
      lease_refs: [intent.lease_ref],
      target_refs: [intent.target_ref],
      prompt_refs: [intent.prompt_ref],
      guard_policy_refs: [intent.guard_policy_ref],
      memory_profile_refs: [intent.memory_profile_ref],
      budget_profile_refs: [intent.budget_profile_ref],
      connector_capability_refs: intent.connector_capability_refs,
      guard_decision: :allow,
      budget_decision: :allow
    }
  end

  @spec admit(Store.t(), map() | keyword() | SkillManifest.t(), map()) ::
          {:ok, Store.t(), AdmissionRecord.t()} | {:error, term()}
  def admit(%Store{} = store, manifest_attrs, verification_refs \\ %{}) do
    with {:ok, manifest} <- SkillContracts.manifest(manifest_attrs),
         :ok <- conformance_passed(verification_refs),
         :ok <- verify_manifest_refs(manifest, verification_refs),
         :ok <- forward_revision(store, manifest) do
      record = admission_record(store, manifest)

      {:ok,
       %Store{
         store
         | admissions: Map.put(store.admissions, manifest.skill_ref, record),
           versions: append_version(store.versions, manifest.skill_ref, manifest.version_ref)
       }, record}
    end
  end

  @spec rollback(Store.t(), String.t(), pos_integer(), map() | keyword()) ::
          {:ok, Store.t(), AdmissionRecord.t()} | {:error, term()}
  def rollback(%Store{} = store, skill_ref, target_revision, attrs \\ %{})
      when is_binary(skill_ref) and is_integer(target_revision) do
    attrs = to_map(attrs)

    with {:ok, current_record} <- fetch_admission(store, skill_ref),
         :ok <- known_revision(store, skill_ref, target_revision),
         :ok <- historical_revision(current_record.version_ref.revision, target_revision),
         {:ok, release_manifest_ref} <-
           required_string(attrs, :release_manifest_ref, current_record.release_manifest_ref),
         {:ok, trace_ref} <- required_string(attrs, :trace_ref, current_record.trace_ref) do
      next_revision = current_record.version_ref.revision + 1

      version_ref = %SkillVersionRef{
        skill_ref: skill_ref,
        version_ref: "#{skill_ref}/revision/#{next_revision}",
        revision: next_revision,
        release_manifest_ref: release_manifest_ref
      }

      %SkillManifest{} = current_manifest = current_record.manifest

      manifest = %SkillManifest{
        current_manifest
        | version_ref: version_ref,
          trace_ref: trace_ref,
          release_manifest_ref: release_manifest_ref
      }

      record = admission_record(store, manifest)

      {:ok,
       %Store{
         store
         | admissions: Map.put(store.admissions, skill_ref, record),
           versions: append_version(store.versions, skill_ref, version_ref)
       }, record}
    end
  end

  @spec invoke(Store.t(), map() | keyword() | SkillInvocationIntent.t(), map()) ::
          {:ok, Store.t(), InvocationRecord.t()} | {:error, term()}
  def invoke(%Store{} = store, intent_attrs, gate_refs \\ %{}) do
    with {:ok, intent} <- SkillContracts.invocation_intent(intent_attrs),
         {:ok, record} <- fetch_admission(store, intent.skill_ref),
         :ok <- same_tenant(record, intent),
         :ok <- intent_matches_manifest(record.manifest, intent),
         :ok <- verify_invocation_refs(intent, gate_refs) do
      invocation = invocation_record(intent)

      {:ok, %Store{store | invocations: [invocation | store.invocations]}, invocation}
    end
  end

  @spec compose(Store.t(), [map() | keyword() | SkillCompositionRef.t()], map() | keyword()) ::
          {:ok, Store.t(), [CompositionRecord.t()]} | {:error, term()}
  def compose(store, composition_attrs, opts \\ [])

  def compose(%Store{} = store, composition_attrs, opts)
      when is_list(composition_attrs) do
    opts = to_map(opts)

    with {:ok, refs} <- composition_refs(composition_attrs),
         :ok <- bounded_compositions(refs, fetch(opts, :max_depth, 5)),
         :ok <- all_skills_admitted(store, refs),
         :ok <- same_tenant_compositions(store, refs),
         :ok <- declared_shared_memory(refs, fetch(opts, :shared_memory_refs, [])),
         :ok <- budget_propagated(refs),
         :ok <- acyclic(refs) do
      records =
        Enum.map(refs, fn ref ->
          %CompositionRecord{
            composition_ref: ref.composition_ref,
            parent_skill_ref: ref.parent_skill_ref,
            child_skill_ref: ref.child_skill_ref,
            tenant_ref: ref.tenant_ref
          }
        end)

      {:ok, %Store{store | compositions: records ++ store.compositions}, records}
    end
  end

  def compose(_store, _composition_attrs, _opts), do: {:error, :invalid_skill_composition}

  defp empty_store(mode, adapter_ref, preflight_ref) do
    %Store{
      persistence_mode: mode,
      durable_adapter_ref: adapter_ref,
      durable_preflight_ref: preflight_ref,
      admissions: %{},
      versions: %{},
      invocations: [],
      compositions: []
    }
  end

  defp admission_record(%Store{} = store, %SkillManifest{} = manifest) do
    %AdmissionRecord{
      admission_ref: "#{manifest.skill_ref}/admission/#{manifest.version_ref.revision}",
      skill_ref: manifest.skill_ref,
      tenant_ref: manifest.tenant_ref,
      manifest: manifest,
      version_ref: manifest.version_ref,
      trace_ref: manifest.trace_ref,
      release_manifest_ref: manifest.release_manifest_ref,
      persistence_mode: store.persistence_mode,
      status: :admitted
    }
  end

  defp invocation_record(%SkillInvocationIntent{} = intent) do
    %InvocationRecord{
      invocation_ref: intent.invocation_ref,
      skill_ref: intent.skill_ref,
      tenant_ref: intent.tenant_ref,
      trace_ref: intent.trace_ref,
      release_manifest_ref: intent.release_manifest_ref,
      gate_refs: %{
        lease_ref: intent.lease_ref,
        target_ref: intent.target_ref,
        prompt_ref: intent.prompt_ref,
        guard_policy_ref: intent.guard_policy_ref,
        memory_profile_ref: intent.memory_profile_ref,
        budget_profile_ref: intent.budget_profile_ref,
        connector_capability_refs: intent.connector_capability_refs
      },
      effect_status: :ready_after_gates,
      provider_effect_started?: false
    }
  end

  defp verify_manifest_refs(%SkillManifest{} = manifest, refs) do
    required_refs = [
      prompt_refs: manifest.prompt_ref,
      guard_policy_refs: manifest.guard_policy_ref,
      eval_suite_refs: manifest.eval_suite_ref,
      memory_profile_refs: manifest.memory_profile_ref,
      budget_profile_refs: manifest.budget_profile_ref
    ]

    case verify_member_gates(refs, required_refs) do
      :ok ->
        all_members_gate(
          refs,
          :connector_capability_refs,
          Enum.map(manifest.capability_bindings, & &1.capability_ref)
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_invocation_refs(%SkillInvocationIntent{} = intent, refs) do
    required_refs = [
      lease_refs: intent.lease_ref,
      target_refs: intent.target_ref,
      prompt_refs: intent.prompt_ref,
      guard_policy_refs: intent.guard_policy_ref,
      memory_profile_refs: intent.memory_profile_ref,
      budget_profile_refs: intent.budget_profile_ref
    ]

    case verify_member_gates(refs, required_refs) do
      :ok -> verify_invocation_tail_refs(intent, refs)
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_member_gates(refs, required_refs) do
    Enum.reduce_while(required_refs, :ok, fn {field, value}, :ok ->
      case member_gate(refs, field, value) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp verify_invocation_tail_refs(%SkillInvocationIntent{} = intent, refs) do
    case all_members_gate(refs, :connector_capability_refs, intent.connector_capability_refs) do
      :ok -> verify_invocation_decisions(refs)
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_invocation_decisions(refs) do
    case allowed_guard_decision(refs) do
      :ok -> allowed_budget_decision(refs)
      {:error, reason} -> {:error, reason}
    end
  end

  defp member_gate(refs, field, value) do
    if value in fetch(refs, field, []) do
      :ok
    else
      {:error, {:skill_gate_ref_missing, field}}
    end
  end

  defp all_members_gate(refs, field, values) do
    allowed = fetch(refs, field, [])

    if Enum.all?(values, &(&1 in allowed)) do
      :ok
    else
      {:error, {:skill_gate_ref_missing, field}}
    end
  end

  defp conformance_passed(refs) do
    case fetch(refs, :conformance_status) do
      value when value in [:passed, "passed"] -> :ok
      _value -> {:error, :skill_conformance_not_passed}
    end
  end

  defp allowed_guard_decision(refs) do
    if fetch(refs, :guard_decision) in @allow_guard_decisions do
      :ok
    else
      {:error, {:skill_invocation_gate_failed, :guard_policy_ref}}
    end
  end

  defp allowed_budget_decision(refs) do
    if fetch(refs, :budget_decision) in @allow_budget_decisions do
      :ok
    else
      {:error, {:skill_invocation_gate_failed, :budget_profile_ref}}
    end
  end

  defp forward_revision(%Store{} = store, %SkillManifest{} = manifest) do
    current =
      store.versions
      |> Map.get(manifest.skill_ref, [])
      |> Enum.map(& &1.revision)
      |> Enum.max(fn -> 0 end)

    if manifest.version_ref.revision > current do
      :ok
    else
      {:error, :skill_version_not_forward}
    end
  end

  defp append_version(versions, skill_ref, version_ref) do
    Map.update(versions, skill_ref, [version_ref], &(&1 ++ [version_ref]))
  end

  defp fetch_admission(%Store{} = store, skill_ref) do
    case Map.fetch(store.admissions, skill_ref) do
      {:ok, record} -> {:ok, record}
      :error -> {:error, :skill_not_admitted}
    end
  end

  defp known_revision(%Store{} = store, skill_ref, target_revision) do
    known? =
      store.versions
      |> Map.get(skill_ref, [])
      |> Enum.any?(&(&1.revision == target_revision))

    if known?, do: :ok, else: {:error, :skill_rollback_target_unknown}
  end

  defp historical_revision(current_revision, target_revision)
       when target_revision < current_revision,
       do: :ok

  defp historical_revision(_current_revision, _target_revision),
    do: {:error, :skill_rollback_requires_historical_revision}

  defp same_tenant(%AdmissionRecord{tenant_ref: tenant_ref}, %SkillInvocationIntent{
         tenant_ref: tenant_ref
       }),
       do: :ok

  defp same_tenant(%AdmissionRecord{}, %SkillInvocationIntent{}),
    do: {:error, :skill_invocation_tenant_mismatch}

  defp intent_matches_manifest(%SkillManifest{} = manifest, %SkillInvocationIntent{} = intent) do
    cond do
      manifest.prompt_ref != intent.prompt_ref ->
        {:error, :skill_invocation_prompt_mismatch}

      manifest.guard_policy_ref != intent.guard_policy_ref ->
        {:error, :skill_invocation_guard_mismatch}

      manifest.eval_suite_ref != intent.eval_suite_ref ->
        {:error, :skill_invocation_eval_mismatch}

      manifest.memory_profile_ref != intent.memory_profile_ref ->
        {:error, :skill_invocation_memory_mismatch}

      manifest.budget_profile_ref != intent.budget_profile_ref ->
        {:error, :skill_invocation_budget_mismatch}

      true ->
        :ok
    end
  end

  defp composition_refs(refs) do
    Enum.reduce_while(refs, {:ok, []}, fn attrs, {:ok, acc} ->
      case SkillContracts.composition_ref(attrs) do
        {:ok, ref} -> {:cont, {:ok, [ref | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp bounded_compositions(refs, max_depth) do
    if Enum.all?(refs, &(&1.max_depth <= max_depth)) do
      :ok
    else
      {:error, :skill_composition_unbounded}
    end
  end

  defp all_skills_admitted(store, refs) do
    case Enum.find(refs, &(not admitted_pair?(store, &1))) do
      nil -> :ok
      _ref -> {:error, :skill_composition_unadmitted_skill}
    end
  end

  defp admitted_pair?(store, ref) do
    Map.has_key?(store.admissions, ref.parent_skill_ref) and
      Map.has_key?(store.admissions, ref.child_skill_ref)
  end

  defp same_tenant_compositions(store, refs) do
    case Enum.find(refs, &(not composition_tenant_valid?(store, &1))) do
      nil -> :ok
      _ref -> {:error, :skill_composition_cross_tenant}
    end
  end

  defp composition_tenant_valid?(store, ref) do
    parent = Map.fetch!(store.admissions, ref.parent_skill_ref)
    child = Map.fetch!(store.admissions, ref.child_skill_ref)

    parent.tenant_ref == ref.tenant_ref and child.tenant_ref == ref.tenant_ref
  end

  defp declared_shared_memory(refs, shared_memory_refs) do
    case Enum.find(refs, &(&1.memory_share_ref not in shared_memory_refs)) do
      nil -> :ok
      _ref -> {:error, :skill_composition_shared_memory_undeclared}
    end
  end

  defp budget_propagated(refs) do
    case Enum.find(refs, &(not present_string?(&1.budget_profile_ref))) do
      nil -> :ok
      _ref -> {:error, :skill_composition_budget_missing}
    end
  end

  defp acyclic(refs) do
    edges = Enum.map(refs, &{&1.parent_skill_ref, &1.child_skill_ref})

    if Enum.any?(edges, fn {parent, child} -> path_exists?(child, parent, edges, []) end) do
      {:error, :skill_composition_cycle}
    else
      :ok
    end
  end

  defp path_exists?(from, to, _edges, _seen) when from == to, do: true

  defp path_exists?(from, to, edges, seen) do
    if from in seen do
      false
    else
      edges
      |> Enum.filter(fn {parent, _child} -> parent == from end)
      |> Enum.any?(fn {_parent, child} -> path_exists?(child, to, edges, [from | seen]) end)
    end
  end

  defp persistence_mode(value) when value in [:memory, "memory"], do: {:ok, :memory}
  defp persistence_mode(value) when value in [:durable, "durable"], do: {:ok, :durable}
  defp persistence_mode(_value), do: {:error, :invalid_skill_store_persistence}

  defp required_string(attrs, field), do: required_string(attrs, field, nil)

  defp required_string(attrs, field, default) do
    case fetch(attrs, field, default) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, {:missing_skill_store_ref, field}}
        else
          {:ok, value}
        end

      _value ->
        {:error, {:missing_skill_store_ref, field}}
    end
  end

  defp to_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp to_map(attrs) when is_map(attrs), do: attrs

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
