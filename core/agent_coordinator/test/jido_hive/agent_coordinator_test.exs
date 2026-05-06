defmodule JidoHive.AgentCoordinatorTest do
  use ExUnit.Case, async: true

  alias JidoHive.AgentCoordinator

  test "spawns only with governed workflow, skill, memory, budget, and trace refs" do
    assert {:ok, record} = AgentCoordinator.spawn_agent(spawn_attrs())
    assert record.effect_status == :coordination_recorded_no_provider_effect
    assert record.store_mode == :memory

    assert {:error, {:missing_ref, :skill_admission_ref}} =
             spawn_attrs() |> Map.delete(:skill_admission_ref) |> AgentCoordinator.spawn_agent()
  end

  test "durable store must be explicit and preflighted" do
    assert {:ok, record} =
             AgentCoordinator.spawn_agent(spawn_attrs(), %{
               mode: :durable,
               adapter_ref: "adapter://coordination/postgres",
               preflight_ref: "preflight://coordination/postgres"
             })

    assert record.store_mode == :durable

    assert {:error, {:missing_ref, :preflight_ref}} =
             AgentCoordinator.store(%{mode: :durable, adapter_ref: "adapter://missing-preflight"})
  end

  test "handoff preserves refs and rejects raw bodies" do
    assert {:ok, handoff} = AgentCoordinator.handoff(handoff_attrs())
    assert handoff.memory_scope_ref == "memory-scope://tenant-a/run-1/shared"

    assert {:error, {:raw_field_rejected, [:agent_message_body]}} =
             handoff_attrs()
             |> Map.put(:agent_message_body, "raw")
             |> AgentCoordinator.handoff()
  end

  test "cancel and supervise require lifecycle refs" do
    assert {:ok, cancel} =
             AgentCoordinator.cancel(%{
               agent_ref: "agent://worker-1",
               tenant_ref: "tenant-a",
               authority_ref: "authority://ops",
               workflow_lifecycle_ref: "workflow://life-1",
               trace_ref: "trace://cancel"
             })

    assert cancel.cancellation_status == :cancel_requested

    assert {:ok, supervision} =
             AgentCoordinator.supervise(%{
               supervision_ref: "supervision://1",
               tenant_ref: "tenant-a",
               authority_ref: "authority://ops",
               workflow_lifecycle_ref: "workflow://life-1",
               trace_ref: "trace://supervise",
               agent_refs: ["agent://worker-1"]
             })

    assert supervision.supervision_status == :bounded
  end

  defp spawn_attrs do
    %{
      agent_ref: "agent://worker-1",
      tenant_ref: "tenant-a",
      authority_ref: "authority://ops",
      installation_ref: "installation://main",
      idempotency_key: "idem-spawn-1",
      trace_ref: "trace://spawn-1",
      persistence_ref: "persistence://memory-default",
      workflow_lifecycle_ref: "workflow://life-1",
      parent_workflow_ref: "workflow://parent-1",
      skill_ref: "skill://research",
      skill_admission_ref: "skill-admission://research/v1",
      memory_scope_ref: "memory-scope://tenant-a/run-1/shared",
      budget_ref: "budget://run-1",
      guard_chain_ref: "guard://chain-1",
      target_ref: "target://local",
      release_manifest_ref: "release://ai-platform/phase-h"
    }
  end

  defp handoff_attrs do
    %{
      handoff_ref: "handoff://1",
      from_agent_ref: "agent://worker-1",
      to_agent_ref: "agent://worker-2",
      tenant_ref: "tenant-a",
      authority_ref: "authority://ops",
      installation_ref: "installation://main",
      idempotency_key: "idem-handoff-1",
      trace_ref: "trace://handoff-1",
      persistence_ref: "persistence://memory-default",
      memory_scope_ref: "memory-scope://tenant-a/run-1/shared",
      budget_ref: "budget://run-1",
      workflow_lifecycle_ref: "workflow://life-1",
      release_manifest_ref: "release://ai-platform/phase-h"
    }
  end
end
