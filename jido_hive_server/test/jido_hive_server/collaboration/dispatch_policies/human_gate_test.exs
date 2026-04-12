defmodule JidoHiveServer.Collaboration.DispatchPolicies.HumanGateTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.DispatchPolicies.HumanGate

  alias JidoHiveServer.Collaboration.Schema.{
    Contribution,
    Participant,
    Room,
    RoomEvent,
    RoomSnapshot
  }

  test "waits for a human contribution after the configured agent assignment completes" do
    snapshot =
      snapshot(%{
        assignments: [
          %{
            id: "asg-1",
            room_id: "room-1",
            participant_id: "agent-1",
            payload: %{},
            status: "completed",
            deadline: nil,
            inserted_at: DateTime.utc_now(),
            meta: %{}
          }
        ]
      })

    {:ok, policy_state, _patch} = HumanGate.init(snapshot, %{})

    {:ok, completion_event} =
      RoomEvent.new(%{
        id: "evt-1",
        room_id: "room-1",
        sequence: 1,
        type: :assignment_completed,
        data: %{"assignment_id" => "asg-1"}
      })

    {:ok, gated_state, %{}} =
      HumanGate.handle_event(completion_event, snapshot, policy_state, %{
        availability: %{},
        now: DateTime.utc_now()
      })

    assert {:wait, :awaiting_human, ^gated_state, %{status: "waiting", phase: "review"}} =
             HumanGate.select(snapshot, %{
               availability: %{"agent-1" => %{}},
               policy_state: gated_state,
               now: DateTime.utc_now()
             })
  end

  test "completes after a human contribution satisfies the gate" do
    snapshot =
      snapshot(%{
        assignments: [
          %{
            id: "asg-1",
            room_id: "room-1",
            participant_id: "agent-1",
            payload: %{},
            status: "completed",
            deadline: nil,
            inserted_at: DateTime.utc_now(),
            meta: %{}
          }
        ],
        contributions: [
          contribution(%{
            id: "ctrb-1",
            assignment_id: "asg-1",
            participant_id: "human-1"
          })
        ]
      })

    {:ok, policy_state, _patch} = HumanGate.init(snapshot, %{})
    gated_state = %{policy_state | gate_assignment_id: "asg-1"}

    assert {:complete, %{reason: :human_gate_satisfied}, next_state,
            %{status: "completed", phase: "review"}} =
             HumanGate.select(snapshot, %{
               availability: %{"agent-1" => %{}},
               policy_state: gated_state,
               now: DateTime.utc_now()
             })

    assert next_state.human_gate_satisfied
  end

  defp snapshot(overrides) do
    {:ok, room} =
      Room.new(%{
        id: "room-1",
        name: "Human gate room",
        status: "waiting",
        config: %{"agent_assignment_limit" => 1}
      })

    base = %RoomSnapshot{
      RoomSnapshot.initial(room, HumanGate.id(), %{})
      | participants: [participant("agent-1", "agent"), participant("human-1", "human")]
    }

    struct(base, overrides)
  end

  defp participant(id, kind) do
    {:ok, participant} =
      Participant.new(%{
        id: id,
        room_id: "room-1",
        kind: kind,
        handle: id,
        meta: %{}
      })

    participant
  end

  defp contribution(attrs) do
    {:ok, contribution} =
      Contribution.new(
        Map.merge(
          %{
            room_id: "room-1",
            kind: "comment",
            payload: %{},
            meta: %{}
          },
          attrs
        )
      )

    contribution
  end
end
