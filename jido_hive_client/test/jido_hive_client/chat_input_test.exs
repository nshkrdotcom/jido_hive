defmodule JidoHiveClient.ChatInputTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.ChatInput

  test "builds a normalized chat input with defaults" do
    {:ok, input} =
      ChatInput.new(%{
        room_id: "room-1",
        participant_id: "alice",
        text: "I think the deploy is broken"
      })

    assert input.room_id == "room-1"
    assert input.participant_id == "alice"
    assert input.participant_role == "collaborator"
    assert input.participant_kind == "human"
    assert input.authority_level == "advisory"
    assert %DateTime{} = input.submitted_at
    assert input.local_context == %{}
  end

  test "accepts explicit authority level" do
    {:ok, input} =
      ChatInput.new(%{
        room_id: "room-1",
        participant_id: "alice",
        text: "Binding decision",
        authority_level: "binding"
      })

    assert input.authority_level == "binding"
  end

  test "requires room_id, participant_id, and text" do
    assert {:error, {:missing_field, "room_id"}} =
             ChatInput.new(%{participant_id: "alice", text: "hi"})

    assert {:error, {:missing_field, "participant_id"}} =
             ChatInput.new(%{room_id: "room-1", text: "hi"})

    assert {:error, {:missing_field, "text"}} =
             ChatInput.new(%{room_id: "room-1", participant_id: "alice"})
  end
end
