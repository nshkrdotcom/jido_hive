defmodule JidoHive.InterAgentMessagingTest do
  use ExUnit.Case, async: true

  alias JidoHive.InterAgentMessaging

  test "routes declared recipients within all budgets" do
    assert {:ok, routed} =
             InterAgentMessaging.route(message_attrs(), %{
               declared_recipient_refs: ["agent://reviewer"],
               fanout_count: 1
             })

    assert routed.delivery_status == :accepted_no_provider_effect
    refute Map.has_key?(InterAgentMessaging.projection(routed), :agent_message_body)
  end

  test "rejects cross-tenant and cross-installation messages" do
    assert {:error, :cross_tenant_message} =
             message_attrs()
             |> Map.put(:recipient_tenant_ref, "tenant-b")
             |> InterAgentMessaging.route(%{declared_recipient_refs: ["agent://reviewer"]})

    assert {:error, :cross_installation_message} =
             message_attrs()
             |> Map.put(:recipient_installation_ref, "installation://other")
             |> InterAgentMessaging.route(%{declared_recipient_refs: ["agent://reviewer"]})
  end

  test "rejects expired budgets, undeclared recipients, fanout, and raw bodies" do
    assert {:error, {:budget_exhausted, :consumed_tokens}} =
             message_attrs()
             |> Map.put(:consumed_tokens, 51)
             |> InterAgentMessaging.route(%{declared_recipient_refs: ["agent://reviewer"]})

    assert {:error, :undeclared_recipient} = InterAgentMessaging.route(message_attrs())

    assert {:error, :unbounded_fanout} =
             InterAgentMessaging.route(message_attrs(), %{
               declared_recipient_refs: ["agent://reviewer"],
               fanout_count: 3
             })

    assert {:error, {:raw_field_rejected, [:agent_message_body]}} =
             message_attrs()
             |> Map.put(:agent_message_body, "raw")
             |> InterAgentMessaging.message_intent()
  end

  defp message_attrs do
    %{
      message_ref: "message://1",
      sender_agent_ref: "agent://writer",
      recipient_agent_ref: "agent://reviewer",
      tenant_ref: "tenant-a",
      installation_ref: "installation://main",
      authority_ref: "authority://ops",
      memory_scope_ref: "memory-scope://tenant-a/run-1/shared",
      context_budget_ref: "context-budget://run-1",
      budget_decision_ref: "budget-decision://allow",
      idempotency_key: "idem-message-1",
      trace_ref: "trace://message-1",
      message_body_ref: "message-body-ref://hash-1",
      redaction_posture: "hash_only",
      token_budget: 50,
      byte_budget: 2048,
      turn_budget: 4,
      wall_clock_budget_ms: 1_000,
      max_fanout: 1
    }
  end
end
