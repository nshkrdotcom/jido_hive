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

  test "normalizes string phase names from dispatch state before building the assignment" do
    snapshot = %{
      room_id: "room-strings-1",
      brief: "Design a substrate.",
      rules: [],
      participants: [
        %{
          participant_id: "worker-01",
          target_id: "target-worker-01",
          participant_kind: "runtime",
          participant_role: "worker",
          capability_id: "workspace.exec.session"
        }
      ],
      context_objects: [],
      dispatch_policy_config: %{"phases" => ["analysis"]},
      dispatch_state: %{
        applied_event_ids: [],
        completed_slots: 0,
        total_slots: 1,
        participant_ids: ["worker-01"],
        phases: ["analysis"]
      }
    }

    assert {:ok, assignment} = RoundRobin.next_assignment(snapshot, ["target-worker-01"])

    assert assignment.phase == "analysis"
    assert assignment.objective == "Analyze the brief and add room-scoped context."

    assert assignment.contribution_contract == %{
             allowed_contribution_types: ["reasoning"],
             allowed_object_types: ["belief", "note", "question"],
             allowed_relation_types: ["derives_from", "references", "contradicts"],
             authority_mode: "advisory_only",
             format: "json_object"
           }
  end
end
