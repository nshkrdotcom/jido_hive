defmodule JidoHiveServer.Collaboration.DispatchPolicies.RoundRobinTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.DispatchPolicies.RoundRobin
  alias JidoHiveServer.Collaboration.Schema.{Participant, Room, RoomSnapshot}

  test "selects the next available agent and advances phase by completed assignment count" do
    snapshot = snapshot()

    {:ok, policy_state, patch} = RoundRobin.init(snapshot, %{})
    assert patch == %{phase: "analysis"}

    assert {:dispatch, ["agent-1"], next_state, %{status: "active", phase: "analysis"}} =
             RoundRobin.select(snapshot, %{
               availability: %{"agent-1" => %{}, "agent-2" => %{}},
               policy_state: policy_state,
               now: DateTime.utc_now()
             })

    assert next_state.cursor == 1
  end

  test "completes once the assignment limit is reached" do
    snapshot =
      snapshot(%{
        room: room(%{config: %{"assignment_limit" => 1}}),
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

    {:ok, policy_state, _patch} = RoundRobin.init(snapshot, %{})

    assert {:complete, %{reason: :assignment_limit_reached}, ^policy_state,
            %{status: "completed"}} =
             RoundRobin.select(snapshot, %{
               availability: %{"agent-1" => %{}},
               policy_state: policy_state,
               now: DateTime.utc_now()
             })
  end

  defp snapshot(overrides \\ %{}) do
    base = %RoomSnapshot{
      RoomSnapshot.initial(room(), RoundRobin.id(), %{})
      | participants: [participant("agent-1"), participant("agent-2")]
    }

    struct(base, overrides)
  end

  defp room(overrides \\ %{}) do
    {:ok, room} =
      Room.new(%{
        id: "room-1",
        name: "Round robin room",
        status: "waiting",
        phase: nil,
        config: %{},
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      })

    struct(room, overrides)
  end

  defp participant(id) do
    {:ok, participant} =
      Participant.new(%{
        id: id,
        room_id: "room-1",
        kind: "agent",
        handle: id,
        meta: %{}
      })

    participant
  end
end
