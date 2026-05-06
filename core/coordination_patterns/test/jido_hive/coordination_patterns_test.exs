defmodule JidoHive.CoordinationPatternsTest do
  use ExUnit.Case, async: true

  alias JidoHive.CoordinationPatterns

  test "accepts bounded reusable coordination patterns" do
    assert {:ok, spec} = CoordinationPatterns.spec(pattern_attrs())
    assert spec.pattern_name == :orchestrator_worker

    projection = CoordinationPatterns.projection(spec)
    assert projection.max_agents == 4
    refute Map.has_key?(projection, :agent_message_body)
  end

  test "rejects unbounded loops, side-effecting replay, and cross-tenant handoff" do
    assert {:error, {:invalid_bound, :max_turns}} =
             pattern_attrs()
             |> Map.put(:max_turns, :unbounded)
             |> CoordinationPatterns.spec()

    assert {:error, :side_effecting_replay_not_allowed} =
             pattern_attrs()
             |> Map.put(:replay_policy, :live_provider_effects)
             |> CoordinationPatterns.spec()

    assert {:error, :implicit_cross_tenant_handoff} =
             pattern_attrs()
             |> Map.put(:handoff_tenant_ref, "tenant-b")
             |> CoordinationPatterns.spec()
  end

  test "rejects unapproved connector use and raw payloads" do
    assert {:error, :unapproved_connector_use} =
             pattern_attrs()
             |> Map.put(:approved_connector_refs, [])
             |> CoordinationPatterns.spec()

    assert {:error, {:raw_field_rejected, [:provider_payload]}} =
             pattern_attrs()
             |> Map.put(:provider_payload, "raw")
             |> CoordinationPatterns.spec()
  end

  defp pattern_attrs do
    %{
      pattern_ref: "coordination-pattern://orchestrator-worker",
      pattern_name: :orchestrator_worker,
      tenant_ref: "tenant-a",
      installation_ref: "installation://main",
      authority_ref: "authority://ops",
      budget_profile_ref: "budget-profile://run-1",
      trace_ref: "trace://pattern-1",
      max_agents: 4,
      max_turns: 8,
      max_messages: 16,
      max_tokens: 4_000,
      cancellation_policy_ref: "cancel-policy://bounded",
      memory_policy_ref: "memory-policy://shared-grants",
      replay_policy: :suppress_provider_effects,
      connector_policy_ref: "connector-policy://approved",
      approved_connector_refs: ["connector://search"],
      redaction_posture: "refs_only"
    }
  end
end
