defmodule JidoHiveServer.Collaboration.ExecutionPlanTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.ExecutionPlan

  test "builds a round-robin execution plan for one or more participants" do
    participants = [
      %{
        participant_id: "worker-01",
        role: "worker",
        target_id: "target-worker-01",
        capability_id: "codex.exec.session"
      },
      %{
        participant_id: "worker-02",
        role: "worker",
        target_id: "target-worker-02",
        capability_id: "codex.exec.session"
      },
      %{
        participant_id: "worker-03",
        role: "worker",
        target_id: "target-worker-03",
        capability_id: "codex.exec.session"
      }
    ]

    assert {:ok, plan} = ExecutionPlan.new(participants)
    assert plan.strategy == "round_robin"
    assert plan.participant_count == 3
    assert plan.planned_turn_count == 9
    assert plan.completed_turn_count == 0
    assert plan.round_robin_index == 0
    assert plan.excluded_target_ids == []

    assert Enum.map(plan.locked_participants, & &1.participant_id) == [
             "worker-01",
             "worker-02",
             "worker-03"
           ]
  end

  test "enforces the 1..39 participant bound" do
    assert {:error, :participant_count_out_of_bounds} = ExecutionPlan.new([])

    participants =
      Enum.map(1..40, fn index ->
        suffix = String.pad_leading(Integer.to_string(index), 2, "0")

        %{
          participant_id: "worker-#{suffix}",
          role: "worker",
          target_id: "target-worker-#{suffix}",
          capability_id: "codex.exec.session"
        }
      end)

    assert {:error, :participant_count_out_of_bounds} = ExecutionPlan.new(participants)
  end

  test "selects the next available participant in round-robin order" do
    assert {:ok, plan} =
             ExecutionPlan.new([
               %{
                 participant_id: "worker-01",
                 role: "worker",
                 target_id: "target-worker-01",
                 capability_id: "codex.exec.session"
               },
               %{
                 participant_id: "worker-02",
                 role: "worker",
                 target_id: "target-worker-02",
                 capability_id: "codex.exec.session"
               },
               %{
                 participant_id: "worker-03",
                 role: "worker",
                 target_id: "target-worker-03",
                 capability_id: "codex.exec.session"
               }
             ])

    assert {:ok, participant, 0} =
             ExecutionPlan.select_next_participant(
               plan,
               ["target-worker-01", "target-worker-02", "target-worker-03"]
             )

    assert participant.participant_id == "worker-01"

    rotated = ExecutionPlan.record_open(plan, 0)

    assert {:ok, participant, 2} =
             ExecutionPlan.select_next_participant(rotated, ["target-worker-03"])

    assert participant.participant_id == "worker-03"
  end

  test "excludes abandoned targets from future room-local assignments" do
    assert {:ok, plan} =
             ExecutionPlan.new([
               %{
                 participant_id: "worker-01",
                 role: "worker",
                 target_id: "target-worker-01",
                 capability_id: "codex.exec.session"
               },
               %{
                 participant_id: "worker-02",
                 role: "worker",
                 target_id: "target-worker-02",
                 capability_id: "codex.exec.session"
               }
             ])

    excluded = ExecutionPlan.record_abandon(plan, "target-worker-01")

    assert excluded.excluded_target_ids == ["target-worker-01"]

    assert {:ok, participant, 1} =
             ExecutionPlan.select_next_participant(
               excluded,
               ["target-worker-01", "target-worker-02"]
             )

    assert participant.participant_id == "worker-02"
  end
end
