defmodule JidoHiveServer.Collaboration.Workflows.DefaultRoundRobinTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.ExecutionPlan
  alias JidoHiveServer.Collaboration.Workflows.DefaultRoundRobin

  test "exposes the default workflow identifier" do
    assert DefaultRoundRobin.id() == "default.round_robin/v1"
  end

  test "reproduces the current proposal critique resolution sequence" do
    {:ok, plan} =
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

    snapshot = %{
      current_turn: %{},
      participants: plan.locked_participants,
      execution_plan: plan,
      turns: [],
      disputes: [],
      context_entries: [],
      brief: "Design a substrate."
    }

    assert {:ok, first} =
             DefaultRoundRobin.next_assignment(snapshot, [
               "target-worker-01",
               "target-worker-02"
             ])

    assert first.phase == "proposal"
    assert first.participant_id == "worker-01"
    assert first.participant_role == "proposer"
  end
end
