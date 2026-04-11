defmodule JidoHive.Switchyard.TUI.StateTest do
  use ExUnit.Case, async: true

  alias JidoHive.Switchyard.TUI.State

  test "moves room and context cursors within bounds" do
    state =
      State.new()
      |> State.put_rooms([
        %{room_id: "room-1"},
        %{room_id: "room-2"}
      ])
      |> State.move_room_cursor(10)

    assert state.room_cursor == 1

    next_state =
      state
      |> State.open_room(%{
        room_id: "room-2",
        selected_context_id: "ctx-2",
        graph_sections: [
          %{title: "QUESTIONS", items: [%{context_id: "ctx-1"}, %{context_id: "ctx-2"}]}
        ],
        detail_index: %{"ctx-2" => %{context_id: "ctx-2"}}
      })
      |> State.move_context_cursor(-1)

    assert next_state.selected_context_id == "ctx-1"
  end
end
