defmodule JidoHive.SharedMemoryFacadeTest do
  use ExUnit.Case, async: true

  alias JidoHive.SharedMemoryFacade

  test "authorizes only explicit shared-memory grants" do
    assert {:ok, decision} =
             SharedMemoryFacade.authorize(intent_attrs(), [grant_attrs()], %{
               known_memory_scope_refs: ["memory-scope://tenant-a/run-1/shared"]
             })

    assert decision.decision == :allow
    refute Map.has_key?(SharedMemoryFacade.projection(decision), :memory_body)

    assert {:error, :missing_shared_memory_grant} =
             SharedMemoryFacade.authorize(intent_attrs(), [], %{
               known_memory_scope_refs: ["memory-scope://tenant-a/run-1/shared"]
             })
  end

  test "rejects unknown scopes, guard-bypassed writes, and private state leakage" do
    assert {:error, :unknown_memory_scope} =
             SharedMemoryFacade.authorize(intent_attrs(), [grant_attrs()], %{
               known_memory_scope_refs: ["memory-scope://other"]
             })

    assert {:error, {:missing_ref, :guard_decision_ref}} =
             intent_attrs()
             |> Map.delete(:guard_decision_ref)
             |> SharedMemoryFacade.intent()

    assert {:error, {:raw_field_rejected, [:skill_private_state]}} =
             grant_attrs()
             |> Map.put(:skill_private_state, "raw")
             |> SharedMemoryFacade.grant()
  end

  test "supports revocation grants as first-class operations" do
    assert {:ok, grant} =
             grant_attrs()
             |> Map.put(:operations, [:revocation])
             |> SharedMemoryFacade.grant()

    assert grant.operations == [:revocation]
  end

  defp grant_attrs do
    %{
      grant_ref: "shared-grant://1",
      tenant_ref: "tenant-a",
      installation_ref: "installation://main",
      agent_ref: "agent://writer",
      memory_scope_ref: "memory-scope://tenant-a/run-1/shared",
      operations: [:shared_read, :shared_write, :handoff, :revocation],
      guard_policy_ref: "guard://memory-write",
      authority_ref: "authority://ops",
      trace_ref: "trace://grant-1",
      redaction_posture: "refs_only"
    }
  end

  defp intent_attrs do
    %{
      intent_ref: "memory-intent://1",
      tenant_ref: "tenant-a",
      installation_ref: "installation://main",
      agent_ref: "agent://writer",
      memory_scope_ref: "memory-scope://tenant-a/run-1/shared",
      operation: :shared_write,
      memory_ref: "memory://shared/fact-1",
      guard_decision_ref: "guard-decision://allow",
      idempotency_key: "idem-memory-1",
      trace_ref: "trace://memory-1",
      redaction_posture: "hash_only"
    }
  end
end
