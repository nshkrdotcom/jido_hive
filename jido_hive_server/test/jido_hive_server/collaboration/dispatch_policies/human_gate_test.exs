defmodule JidoHiveServer.Collaboration.DispatchPolicies.HumanGateTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.DispatchPolicies.HumanGate

  test "blocks on authority after automatic assignments are complete" do
    snapshot = %{
      room_id: "room-1",
      brief: "Design a substrate.",
      rules: [],
      participants: [
        %{
          participant_id: "worker-01",
          target_id: "target-worker-01",
          participant_kind: "runtime",
          participant_role: "worker"
        }
      ],
      assignments: [%{assignment_id: "asn-1", status: "completed"}],
      contributions: [%{participant_id: "worker-01", authority_level: "advisory"}],
      context_objects: [],
      dispatch_policy_config: %{},
      dispatch_state:
        HumanGate.init_state(%{
          participants: [%{participant_kind: "runtime"}],
          dispatch_policy_config: %{}
        })
    }

    snapshot =
      put_in(snapshot.dispatch_state.completed_slots, snapshot.dispatch_state.total_slots)

    assert {:awaiting_authority, "awaiting_authority"} =
             HumanGate.next_action(snapshot, ["target-worker-01"])
  end
end
