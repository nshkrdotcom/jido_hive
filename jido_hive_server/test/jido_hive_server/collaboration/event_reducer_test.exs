defmodule JidoHiveServer.Collaboration.EventReducerTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.EventReducer
  alias JidoHiveServer.Collaboration.ExecutionPlan
  alias JidoHiveServer.Collaboration.Schema.RoomEvent
  alias JidoHiveServer.Collaboration.Workflows.DefaultRoundRobin

  test "turn_opened updates current_turn, turns, and workflow counters" do
    {:ok, plan} = ExecutionPlan.new(participants())

    snapshot =
      room_snapshot(%{
        execution_plan: plan,
        workflow_id: DefaultRoundRobin.id(),
        workflow_config: %{},
        workflow_state: %{applied_event_ids: []}
      })

    {:ok, event} =
      RoomEvent.new(%{
        event_id: "evt-open-1",
        room_id: "room-1",
        type: :turn_opened,
        payload: %{
          job_id: "job-1",
          plan_slot_index: 0,
          participant_id: "worker-01",
          participant_role: "proposer",
          target_id: "target-worker-01",
          capability_id: "codex.exec.session",
          phase: "proposal",
          objective: "Open the first turn.",
          round: 1,
          session: %{"provider" => "codex"},
          collaboration_envelope: %{"turn" => %{"phase" => "proposal"}}
        },
        recorded_at: DateTime.utc_now()
      })

    updated = EventReducer.apply_event(snapshot, event)

    assert updated.current_turn.job_id == "job-1"
    assert List.last(updated.turns).job_id == "job-1"
    assert updated.execution_plan.round_robin_index == 1
    assert updated.phase == "proposal"
    assert updated.status == "running"
    assert updated.workflow_state.applied_event_ids == ["evt-open-1"]
  end

  test "turn_completed materializes entries and resolves targeted disputes" do
    {:ok, plan} = ExecutionPlan.new(participants())

    snapshot =
      room_snapshot(%{
        execution_plan: ExecutionPlan.record_open(plan, 0),
        workflow_id: DefaultRoundRobin.id(),
        workflow_config: %{},
        workflow_state: %{applied_event_ids: []},
        phase: "critique",
        status: "running",
        next_entry_seq: 2,
        next_dispute_seq: 2,
        current_turn: %{
          job_id: "job-critique-1",
          target_id: "target-worker-01",
          phase: "critique"
        },
        turns: [
          %{
            job_id: "job-critique-1",
            participant_id: "worker-01",
            participant_role: "critic",
            target_id: "target-worker-01",
            capability_id: "codex.exec.session",
            phase: "critique",
            round: 1,
            status: :running
          }
        ],
        disputes: [
          %{
            dispute_id: "dispute:1",
            title: "Existing dispute",
            severity: "high",
            status: :open,
            opened_by_entry_ref: "objection:1",
            target_entry_refs: ["claim:1"]
          }
        ]
      })

    {:ok, event} =
      RoomEvent.new(%{
        event_id: "evt-complete-1",
        room_id: "room-1",
        type: :turn_completed,
        payload: %{
          job_id: "job-critique-1",
          participant_id: "worker-01",
          participant_role: "critic",
          status: "completed",
          summary: "resolved dispute",
          actions: [
            %{
              "op" => "REVISE",
              "title" => "Ledger",
              "body" => "Introduce contradiction ledger.",
              "targets" => [%{"dispute_id" => "dispute:1"}]
            }
          ],
          tool_events: [],
          events: [],
          approvals: [],
          artifacts: [],
          execution: %{"status" => "completed"}
        },
        recorded_at: DateTime.utc_now()
      })

    updated = EventReducer.apply_event(snapshot, event)

    assert updated.current_turn == %{}
    assert updated.execution_plan.completed_turn_count == 1
    assert [%{entry_type: "revision", entry_ref: "revision:2"}] = updated.context_entries
    assert Enum.all?(updated.disputes, &(&1.status == :resolved))
    assert updated.workflow_state.applied_event_ids == ["evt-complete-1"]
  end

  test "turn_abandoned excludes the target without consuming completion budget" do
    {:ok, plan} = ExecutionPlan.new(participants())

    snapshot =
      room_snapshot(%{
        execution_plan: ExecutionPlan.record_open(plan, 0),
        workflow_id: DefaultRoundRobin.id(),
        workflow_config: %{},
        workflow_state: %{applied_event_ids: []},
        current_turn: %{job_id: "job-1"},
        turns: [
          %{
            job_id: "job-1",
            target_id: "target-worker-01",
            status: :running
          }
        ]
      })

    {:ok, event} =
      RoomEvent.new(%{
        event_id: "evt-abandon-1",
        room_id: "room-1",
        type: :turn_abandoned,
        payload: %{job_id: "job-1", reason: "timed out"},
        recorded_at: DateTime.utc_now()
      })

    updated = EventReducer.apply_event(snapshot, event)

    assert updated.current_turn == %{}
    assert updated.execution_plan.completed_turn_count == 0
    assert updated.execution_plan.excluded_target_ids == ["target-worker-01"]
    assert [%{status: :abandoned}] = updated.turns
    assert updated.workflow_state.applied_event_ids == ["evt-abandon-1"]
  end

  test "ignores duplicate event ids" do
    snapshot =
      room_snapshot(%{
        workflow_state: %{applied_event_ids: ["evt-dup-1"]}
      })

    {:ok, event} =
      RoomEvent.new(%{
        event_id: "evt-dup-1",
        room_id: "room-1",
        type: :runtime_state_changed,
        payload: %{status: "blocked", phase: "critique"},
        recorded_at: DateTime.utc_now()
      })

    assert EventReducer.apply_event(snapshot, event) == snapshot
  end

  defp participants do
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
    ]
  end

  defp room_snapshot(overrides) do
    Map.merge(
      %{
        room_id: "room-1",
        session_id: "session-1",
        brief: "Design a generalized collaboration substrate.",
        rules: [],
        participants: participants(),
        turns: [],
        context_entries: [],
        disputes: [],
        current_turn: %{},
        execution_plan: %{},
        status: "idle",
        phase: "idle",
        round: 0,
        next_entry_seq: 1,
        next_dispute_seq: 1,
        workflow_id: DefaultRoundRobin.id(),
        workflow_config: %{},
        workflow_state: %{applied_event_ids: []}
      },
      overrides
    )
  end
end
