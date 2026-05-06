defmodule JidoHive.SkillConformanceContractsTest do
  use ExUnit.Case, async: true
  use JidoHive.SkillConformanceContracts

  test "external author helper accepts safe ref-only manifests" do
    manifest = assert_safe_skill_manifest(valid_manifest())

    assert manifest.skill_ref == "skill://phase-g/external"
    assert manifest.conformance_ref == "conformance://phase-g/external"
  end

  test "external author helper fails unsafe raw manifest fields" do
    reason =
      valid_manifest()
      |> Map.put(:provider_payload, %{payload_ref: "provider://private"})
      |> refute_safe_skill_manifest()

    assert {:raw_skill_field_forbidden, [:provider_payload]} = reason
  end

  test "external author helper fails missing required refs" do
    reason =
      valid_manifest()
      |> Map.delete(:guard_policy_ref)
      |> refute_safe_skill_manifest()

    assert {:missing_skill_ref, :guard_policy_ref} = reason
  end

  defp valid_manifest do
    %{
      skill_ref: "skill://phase-g/external",
      version_ref: %{
        skill_ref: "skill://phase-g/external",
        version_ref: "skill-version://phase-g/external/1",
        revision: 1,
        release_manifest_ref: "release://phase-g"
      },
      tenant_ref: "tenant://phase-g",
      authority_ref: "authority://phase-g",
      installation_ref: "installation://phase-g",
      idempotency_key: "idem-phase-g-external",
      trace_ref: "trace://phase-g/external",
      persistence_profile_ref: "persistence://memory/default",
      release_manifest_ref: "release://phase-g",
      prompt_ref: "prompt://phase-g/external",
      tool_refs: ["tool://external"],
      memory_profile_ref: "memory://phase-g/default",
      guard_policy_ref: "guard://phase-g/default",
      eval_suite_ref: "eval://phase-g/default",
      budget_profile_ref: "budget://phase-g/default",
      conformance_ref: "conformance://phase-g/external",
      capability_bindings: [
        %{
          binding_ref: "binding://phase-g/external",
          capability_ref: "capability://phase-g/external",
          connector_ref: "connector://phase-g/external",
          capability_id: "external.run",
          tenant_ref: "tenant://phase-g",
          scope_ref: "scope://phase-g/external",
          contract_version: "connector-sdk.v1"
        }
      ]
    }
  end
end
