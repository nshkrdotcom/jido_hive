defmodule JidoHive.SkillEngineTest do
  use ExUnit.Case, async: true

  alias JidoHive.SkillContracts
  alias JidoHive.SkillEngine

  test "skill store defaults to memory and durable opt-in preflights" do
    assert {:ok, store} = SkillEngine.new_store()
    assert store.persistence_mode == :memory

    assert {:error,
            {:durable_skill_store_preflight_failed,
             {:missing_skill_store_ref, :durable_adapter_ref}}} =
             SkillEngine.new_store(%{persistence: :durable})

    assert {:ok, durable_store} =
             SkillEngine.new_store(%{
               persistence: :durable,
               durable_adapter_ref: "adapter://skill-store",
               durable_preflight_ref: "preflight://skill-store"
             })

    assert durable_store.persistence_mode == :durable
  end

  test "admission verifies refs and rejects missing connector capability before effects" do
    manifest = SkillContracts.manifest!(valid_manifest("research", 1))
    refs = SkillEngine.verification_refs_for(manifest)
    assert {:ok, store} = SkillEngine.new_store()

    assert {:ok, store, record} = SkillEngine.admit(store, manifest, refs)
    assert record.status == :admitted
    assert store.persistence_mode == :memory

    summary_manifest = SkillContracts.manifest!(valid_manifest("summary", 1))

    missing_connector =
      summary_manifest
      |> SkillEngine.verification_refs_for()
      |> Map.put(:connector_capability_refs, [])

    assert {:error, {:skill_gate_ref_missing, :connector_capability_refs}} =
             SkillEngine.admit(store, summary_manifest, missing_connector)
  end

  test "versioning is forward-only and rollback creates a new revision" do
    assert {:ok, store} = SkillEngine.new_store()
    manifest_v1 = SkillContracts.manifest!(valid_manifest("research", 1))
    refs = SkillEngine.verification_refs_for(manifest_v1)
    assert {:ok, store, _record} = SkillEngine.admit(store, manifest_v1, refs)

    assert {:error, :skill_version_not_forward} =
             SkillEngine.admit(store, valid_manifest("research", 1), refs)

    manifest_v2 = SkillContracts.manifest!(valid_manifest("research", 2))
    refs_v2 = SkillEngine.verification_refs_for(manifest_v2)
    assert {:ok, store, _record} = SkillEngine.admit(store, manifest_v2, refs_v2)

    assert {:ok, _store, rollback_record} =
             SkillEngine.rollback(store, "skill://phase-g/research", 1,
               release_manifest_ref: "release://phase-g/rollback",
               trace_ref: "trace://phase-g/rollback"
             )

    assert rollback_record.version_ref.revision == 3
    assert rollback_record.release_manifest_ref == "release://phase-g/rollback"
  end

  test "invocation requires gates before provider readiness" do
    assert {:ok, store} = SkillEngine.new_store()
    manifest = SkillContracts.manifest!(valid_manifest("research", 1))

    assert {:ok, store, _record} =
             SkillEngine.admit(store, manifest, SkillEngine.verification_refs_for(manifest))

    intent = SkillContracts.invocation_intent!(valid_intent("research"))
    gates = SkillEngine.invocation_gate_refs_for(intent)

    assert {:ok, _store, invocation} = SkillEngine.invoke(store, intent, gates)
    assert invocation.effect_status == :ready_after_gates
    assert invocation.provider_effect_started? == false

    exhausted_budget = Map.put(gates, :budget_decision, :deny_hard_exhausted)

    assert {:error, {:skill_invocation_gate_failed, :budget_profile_ref}} =
             SkillEngine.invoke(store, intent, exhausted_budget)
  end

  test "composition rejects cycles and undeclared shared memory" do
    assert {:ok, store} = SkillEngine.new_store()
    assert {:ok, store, _record} = admit_skill(store, "parent", 1)
    assert {:ok, store, _record} = admit_skill(store, "child", 1)

    composition = composition("parent", "child", "memory-share://phase-g")

    assert {:ok, _store, records} =
             SkillEngine.compose(store, [composition],
               shared_memory_refs: ["memory-share://phase-g"],
               max_depth: 2
             )

    assert hd(records).composition_ref == "composition://phase-g/parent/child"

    assert {:error, :skill_composition_shared_memory_undeclared} =
             SkillEngine.compose(store, [composition], shared_memory_refs: [])

    cycle = [
      composition("parent", "child", "memory-share://phase-g"),
      composition("child", "parent", "memory-share://phase-g")
    ]

    assert {:error, :skill_composition_cycle} =
             SkillEngine.compose(store, cycle,
               shared_memory_refs: ["memory-share://phase-g"],
               max_depth: 2
             )
  end

  defp admit_skill(store, name, revision) do
    manifest = SkillContracts.manifest!(valid_manifest(name, revision))
    SkillEngine.admit(store, manifest, SkillEngine.verification_refs_for(manifest))
  end

  defp valid_manifest(name, revision) do
    skill_ref = "skill://phase-g/#{name}"

    %{
      skill_ref: skill_ref,
      version_ref: %{
        skill_ref: skill_ref,
        version_ref: "skill-version://phase-g/#{name}/#{revision}",
        revision: revision,
        release_manifest_ref: "release://phase-g"
      },
      tenant_ref: "tenant://phase-g",
      authority_ref: "authority://phase-g",
      installation_ref: "installation://phase-g",
      idempotency_key: "idem-phase-g-#{name}-#{revision}",
      trace_ref: "trace://phase-g/#{name}",
      persistence_profile_ref: "persistence://memory/default",
      release_manifest_ref: "release://phase-g",
      prompt_ref: "prompt://phase-g/#{name}",
      tool_refs: ["tool://search"],
      memory_profile_ref: "memory://phase-g/default",
      guard_policy_ref: "guard://phase-g/default",
      eval_suite_ref: "eval://phase-g/default",
      budget_profile_ref: "budget://phase-g/default",
      conformance_ref: "conformance://phase-g/passed",
      capability_bindings: [
        %{
          binding_ref: "binding://phase-g/#{name}",
          capability_ref: "capability://phase-g/#{name}",
          connector_ref: "connector://phase-g/search",
          capability_id: "#{name}.search",
          tenant_ref: "tenant://phase-g",
          scope_ref: "scope://phase-g/search",
          contract_version: "connector-sdk.v1"
        }
      ]
    }
  end

  defp valid_intent(name) do
    %{
      invocation_ref: "skill-invocation://phase-g/#{name}",
      skill_ref: "skill://phase-g/#{name}",
      tenant_ref: "tenant://phase-g",
      authority_ref: "authority://phase-g",
      installation_ref: "installation://phase-g",
      lease_ref: "lease://phase-g",
      target_ref: "target://phase-g",
      prompt_ref: "prompt://phase-g/#{name}",
      memory_profile_ref: "memory://phase-g/default",
      guard_policy_ref: "guard://phase-g/default",
      eval_suite_ref: "eval://phase-g/default",
      budget_profile_ref: "budget://phase-g/default",
      connector_capability_refs: ["capability://phase-g/#{name}"],
      trace_ref: "trace://phase-g/#{name}/invoke",
      idempotency_key: "idem-phase-g-#{name}-invoke",
      release_manifest_ref: "release://phase-g"
    }
  end

  defp composition(parent, child, memory_share_ref) do
    %{
      composition_ref: "composition://phase-g/#{parent}/#{child}",
      parent_skill_ref: "skill://phase-g/#{parent}",
      child_skill_ref: "skill://phase-g/#{child}",
      tenant_ref: "tenant://phase-g",
      memory_share_ref: memory_share_ref,
      budget_profile_ref: "budget://phase-g/default",
      max_depth: 2
    }
  end
end
