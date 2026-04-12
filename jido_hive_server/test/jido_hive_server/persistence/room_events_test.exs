defmodule JidoHiveServer.Persistence.RoomEventsTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias JidoHiveServer.Collaboration.Schema.{Room, RoomEvent, RoomSnapshot}
  alias JidoHiveServer.Persistence
  alias JidoHiveServer.Persistence.RoomSnapshotRecord
  alias JidoHiveServer.Repo

  test "appends and lists room events by sequence" do
    recorded_at = DateTime.utc_now()

    {:ok, first} =
      RoomEvent.new(%{
        id: "evt-room-1",
        room_id: "room-1",
        sequence: 1,
        type: :room_created,
        data: %{"room" => %{"id" => "room-1", "name" => "First room"}},
        inserted_at: recorded_at
      })

    {:ok, second} =
      RoomEvent.new(%{
        id: "evt-room-2",
        room_id: "room-1",
        sequence: 2,
        type: :assignment_created,
        data: %{
          "assignment" => %{
            "id" => "asg-1",
            "room_id" => "room-1",
            "participant_id" => "participant-1",
            "payload" => %{"phase" => "analysis"},
            "status" => "pending",
            "meta" => %{}
          }
        },
        inserted_at: recorded_at
      })

    assert :ok = Persistence.append_room_events("room-1", [first, second])

    assert {:ok, [listed_first, listed_second]} = Persistence.list_room_events("room-1")
    assert listed_first.id == "evt-room-1"
    assert listed_first.sequence == 1
    assert listed_first.type == :room_created
    assert listed_second.id == "evt-room-2"
    assert listed_second.sequence == 2
    assert listed_second.type == :assignment_created
  end

  test "lists room events after a sequence cursor" do
    assert :ok =
             Persistence.append_room_events("room-1", [
               event("evt-1", 1, :room_created),
               event("evt-2", 2, :participant_joined),
               event("evt-3", 3, :contribution_submitted)
             ])

    assert {:ok, [event]} = Persistence.list_room_events_after("room-1", 2)
    assert event.id == "evt-3"
    assert event.sequence == 3
  end

  test "rejects non-canonical snapshot payloads" do
    Repo.insert!(%RoomSnapshotRecord{
      room_id: "room-legacy",
      snapshot: %{"version" => "legacy"}
    })

    assert {:error, :invalid_snapshot_format} = Persistence.fetch_room_snapshot("room-legacy")
  end

  test "round-trips canonical room snapshots" do
    {:ok, room} =
      Room.new(%{
        id: "room-1",
        name: "Canonical room",
        status: "waiting",
        config: %{}
      })

    snapshot = RoomSnapshot.initial(room, "round_robin/v2", %{"cursor" => 0})

    assert {:ok, persisted} = Persistence.persist_room_snapshot(snapshot)
    assert persisted.version == RoomSnapshot.version()

    assert {:ok, reloaded} = Persistence.fetch_room_snapshot("room-1")
    assert reloaded.version == RoomSnapshot.version()
    assert reloaded.room.name == "Canonical room"
    assert reloaded.dispatch.policy_id == "round_robin/v2"
  end

  defp event(id, sequence, type) do
    {:ok, event} =
      RoomEvent.new(%{
        id: id,
        room_id: "room-1",
        sequence: sequence,
        type: type,
        data: event_data(type)
      })

    event
  end

  defp event_data(:room_created), do: %{"room" => %{"id" => "room-1", "name" => "Room 1"}}

  defp event_data(:participant_joined) do
    %{
      "participant" => %{
        "id" => "participant-1",
        "room_id" => "room-1",
        "kind" => "human",
        "handle" => "alice",
        "meta" => %{}
      }
    }
  end

  defp event_data(:contribution_submitted) do
    %{
      "contribution" => %{
        "id" => "ctrb-1",
        "room_id" => "room-1",
        "participant_id" => "participant-1",
        "kind" => "comment",
        "payload" => %{"text" => "hello"},
        "meta" => %{}
      }
    }
  end
end
