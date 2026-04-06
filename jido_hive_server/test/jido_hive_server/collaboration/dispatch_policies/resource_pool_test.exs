defmodule JidoHiveServer.Collaboration.DispatchPolicies.ResourcePoolTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.DispatchPolicies.ResourcePool

  test "selects the least-used available runtime participant" do
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
        },
        %{
          participant_id: "worker-02",
          target_id: "target-worker-02",
          participant_kind: "runtime",
          participant_role: "worker"
        }
      ],
      assignments: [
        %{participant_id: "worker-01", status: "completed"}
      ],
      context_objects: [],
      dispatch_policy_config: %{"assignment_count" => 2},
      dispatch_state:
        ResourcePool.init_state(%{
          participants: [],
          dispatch_policy_config: %{"assignment_count" => 2}
        })
    }

    assert {:ok, assignment} =
             ResourcePool.next_assignment(snapshot, ["target-worker-01", "target-worker-02"])

    assert assignment.participant_id == "worker-02"
  end
end
