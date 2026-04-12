defmodule JidoHiveServer.Collaboration.DispatchPolicies.ResourcePoolTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.DispatchPolicies.ResourcePool
  alias JidoHiveServer.Collaboration.Schema.{Participant, Room, RoomSnapshot}

  test "selects the least-used available agent participant" do
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

    {:ok, policy_state, _patch} = ResourcePool.init(snapshot, %{})

    assert {:dispatch, ["agent-2"], ^policy_state, %{status: "active"}} =
             ResourcePool.select(snapshot, %{
               availability: %{"agent-1" => %{}, "agent-2" => %{}},
               policy_state: policy_state,
               now: DateTime.utc_now()
             })
  end

  defp snapshot(overrides) do
    {:ok, room} =
      Room.new(%{
        id: "room-1",
        name: "Resource pool room",
        status: "waiting",
        config: %{"assignment_limit" => 3}
      })

    base = %RoomSnapshot{
      RoomSnapshot.initial(room, ResourcePool.id(), %{})
      | participants: [participant("agent-1"), participant("agent-2")]
    }

    struct(base, overrides)
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
