defmodule JidoHiveServer.Collaboration.DispatchPolicies.RoundRobinTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.DispatchPolicies.RoundRobin

  test "selects the next participant and phase from dispatch state" do
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
      context_objects: [],
      dispatch_policy_config: %{},
      dispatch_state:
        RoundRobin.init_state(%{
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
          dispatch_policy_config: %{}
        })
    }

    assert {:ok, assignment} =
             RoundRobin.next_assignment(snapshot, ["target-worker-01", "target-worker-02"])

    assert assignment.participant_id == "worker-01"
    assert assignment.phase == "analysis"
  end
end
