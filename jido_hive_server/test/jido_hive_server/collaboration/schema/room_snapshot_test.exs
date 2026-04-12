defmodule JidoHiveServer.Collaboration.Schema.RoomSnapshotTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.Schema.{Room, RoomSnapshot}

  test "builds an initial canonical room snapshot" do
    {:ok, room} =
      Room.new(%{
        id: "room-1",
        name: "Canonical room",
        status: "waiting",
        config: %{}
      })

    snapshot = RoomSnapshot.initial(room, "round_robin", %{"turn" => 0})

    assert snapshot.version == RoomSnapshot.version()
    assert snapshot.room.id == "room-1"
    assert snapshot.dispatch.policy_id == "round_robin"
    assert snapshot.dispatch.policy_state == %{"turn" => 0}
    assert snapshot.clocks.next_event_sequence == 1
    assert snapshot.replay.checkpoint_event_sequence == 0
  end

  test "rejects legacy snapshot versions" do
    assert {:error, :invalid_snapshot_version} =
             RoomSnapshot.new(%{
               version: "legacy",
               room: %{},
               participants: [],
               assignments: [],
               contributions: [],
               dispatch: %{},
               clocks: %{},
               replay: %{}
             })
  end

  test "recognizes valid canonical snapshot maps" do
    {:ok, room} =
      Room.new(%{
        id: "room-1",
        name: "Canonical room",
        status: "waiting",
        config: %{}
      })

    snapshot = RoomSnapshot.initial(room, "round_robin", %{})

    assert RoomSnapshot.valid_snapshot_map?(RoomSnapshot.to_map(snapshot))
    refute RoomSnapshot.valid_snapshot_map?(%{"version" => "legacy"})
  end
end
