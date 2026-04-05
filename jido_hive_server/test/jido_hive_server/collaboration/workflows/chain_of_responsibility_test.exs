defmodule JidoHiveServer.Collaboration.Workflows.ChainOfResponsibilityTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.ExecutionPlan
  alias JidoHiveServer.Collaboration.Workflows.ChainOfResponsibility

  test "uses configured phases to derive planned turn count and assignments" do
    config = %{
      "phases" => [
        %{"phase" => "draft", "participant_role" => "author"},
        %{"phase" => "review", "participant_role" => "reviewer"}
      ]
    }

    {:ok, plan} =
      ExecutionPlan.new(
        [
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
        ],
        stages: ChainOfResponsibility.stages(config)
      )

    assert plan.stage_count == 2
    assert plan.planned_turn_count == 4
    assert Enum.map(plan.stages, & &1.phase) == ["draft", "review"]

    snapshot = %{
      current_turn: %{},
      participants: plan.locked_participants,
      execution_plan: plan,
      turns: [],
      disputes: [],
      context_entries: [],
      brief: "Design a flexible collaboration workflow."
    }

    assert {:ok, assignment} =
             ChainOfResponsibility.next_assignment(snapshot, [
               "target-worker-01",
               "target-worker-02"
             ])

    assert assignment.phase == "draft"
    assert assignment.participant_role == "author"
  end
end
