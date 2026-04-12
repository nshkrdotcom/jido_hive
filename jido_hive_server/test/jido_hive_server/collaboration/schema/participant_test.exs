defmodule JidoHiveServer.Collaboration.Schema.ParticipantTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.Schema.Participant

  test "builds a canonical participant" do
    assert {:ok, participant} =
             Participant.new(%{
               id: "participant-1",
               room_id: "room-1",
               kind: "agent",
               handle: "worker-01",
               meta: %{"runtime_kind" => "codex"}
             })

    assert participant.id == "participant-1"
    assert participant.room_id == "room-1"
    assert participant.kind == "agent"
    assert participant.handle == "worker-01"
    assert participant.meta == %{"runtime_kind" => "codex"}
    assert %DateTime{} = participant.joined_at
  end

  test "requires canonical id and handle fields" do
    assert {:error, {:missing_field, "id"}} =
             Participant.new(%{
               room_id: "room-1",
               kind: "human",
               handle: "alice"
             })

    assert {:error, {:missing_field, "handle"}} =
             Participant.new(%{
               id: "participant-1",
               room_id: "room-1",
               kind: "human"
             })
  end
end
