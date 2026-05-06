defmodule JidoHive.SkillContractsTest do
  use ExUnit.Case, async: true

  alias JidoHive.SkillContracts

  test "skill manifest requires governed refs" do
    assert {:ok, manifest} = SkillContracts.manifest(valid_manifest())

    assert manifest.skill_ref == "skill://phase-g/research"
    assert manifest.version_ref.revision == 1
    assert manifest.prompt_ref == "prompt://phase-g/research"
    assert manifest.tool_refs == ["tool://search", "tool://summarize"]

    assert manifest.capability_bindings |> hd() |> Map.fetch!(:capability_ref) ==
             "capability://connector/search"
  end

  test "skill manifest rejects raw bodies and private state" do
    attrs = Map.put(valid_manifest(), :prompt_body, "not admitted")
    assert {:error, {:raw_skill_field_forbidden, [:prompt_body]}} = SkillContracts.manifest(attrs)

    nested =
      valid_manifest()
      |> Map.put(:metadata, %{private_state: %{step: "hidden"}})

    assert {:error, {:raw_skill_field_forbidden, [:metadata, :private_state]}} =
             SkillContracts.manifest(nested)
  end

  test "skill manifest rejects duplicate connector capability bindings" do
    binding = capability_binding("binding://search", "capability://connector/search")

    attrs =
      valid_manifest()
      |> Map.put(:capability_bindings, [binding, Map.put(binding, :binding_ref, "binding://two")])

    assert {:error, :duplicate_skill_capability_binding} = SkillContracts.manifest(attrs)
  end

  test "skill invocation intent requires all effect gates" do
    assert {:ok, intent} = SkillContracts.invocation_intent(valid_intent())
    assert intent.lease_ref == "lease://phase-g"

    attrs = Map.delete(valid_intent(), :target_ref)
    assert {:error, {:missing_skill_ref, :target_ref}} = SkillContracts.invocation_intent(attrs)
  end

  test "skill projection and trace projection contain refs only" do
    manifest = SkillContracts.manifest!(valid_manifest())

    projection = SkillContracts.projection(manifest)
    trace_projection = SkillContracts.trace_projection(manifest)

    assert projection.redaction_posture == "refs_only"
    assert trace_projection.redaction_posture == "private_state_redacted"
    refute Map.has_key?(projection, :private_state)
    refute Map.has_key?(trace_projection, :provider_payload)
  end

  def valid_manifest do
    %{
      skill_ref: "skill://phase-g/research",
      version_ref: %{
        skill_ref: "skill://phase-g/research",
        version_ref: "skill-version://phase-g/research/1",
        revision: 1,
        release_manifest_ref: "release://phase-g"
      },
      tenant_ref: "tenant://phase-g",
      authority_ref: "authority://phase-g",
      installation_ref: "installation://phase-g",
      idempotency_key: "idem-phase-g-skill",
      trace_ref: "trace://phase-g/manifest",
      persistence_profile_ref: "persistence://memory/default",
      release_manifest_ref: "release://phase-g",
      prompt_ref: "prompt://phase-g/research",
      tool_refs: ["tool://search", "tool://summarize"],
      memory_profile_ref: "memory://phase-g/default",
      guard_policy_ref: "guard://phase-g/default",
      eval_suite_ref: "eval://phase-g/default",
      budget_profile_ref: "budget://phase-g/default",
      conformance_ref: "conformance://phase-g/passed",
      capability_bindings: [
        capability_binding("binding://search", "capability://connector/search")
      ]
    }
  end

  def valid_intent do
    %{
      invocation_ref: "skill-invocation://phase-g/one",
      skill_ref: "skill://phase-g/research",
      tenant_ref: "tenant://phase-g",
      authority_ref: "authority://phase-g",
      installation_ref: "installation://phase-g",
      lease_ref: "lease://phase-g",
      target_ref: "target://phase-g",
      prompt_ref: "prompt://phase-g/research",
      memory_profile_ref: "memory://phase-g/default",
      guard_policy_ref: "guard://phase-g/default",
      eval_suite_ref: "eval://phase-g/default",
      budget_profile_ref: "budget://phase-g/default",
      connector_capability_refs: ["capability://connector/search"],
      trace_ref: "trace://phase-g/invocation",
      idempotency_key: "idem-phase-g-invoke",
      release_manifest_ref: "release://phase-g"
    }
  end

  defp capability_binding(binding_ref, capability_ref) do
    %{
      binding_ref: binding_ref,
      capability_ref: capability_ref,
      connector_ref: "connector://search",
      capability_id: "search.query",
      tenant_ref: "tenant://phase-g",
      scope_ref: "scope://search/read",
      contract_version: "connector-sdk.v1"
    }
  end
end
