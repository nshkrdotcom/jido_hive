defmodule JidoHiveConsole.ScreenUITest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Paragraph, Popup}
  alias JidoHiveConsole.{Model, ScreenUI}

  test "pane joins lines into paragraph text with a titled block" do
    assert %Paragraph{text: "Line 1\nLine 2", wrap: true, block: %{title: "Guide"}} =
             ScreenUI.pane("Guide", ["Line 1", "Line 2"], wrap: true)
  end

  test "help popup widgets stay within the frame and include guide copy" do
    state = Model.new([]) |> Map.put(:help_visible, true)

    assert [
             {%Popup{block: %{title: "Guide"}, fixed_width: 124, content: %Paragraph{text: text}},
              %Rect{width: 140, height: 32}}
           ] =
             ScreenUI.help_popup_widgets(%{width: 140, height: 32}, state, "Guide", [
               "Line 1",
               "Line 2"
             ])

    assert text =~ "Line 1"
    assert text =~ "Ctrl+G or F1 opens it again. F2 shows debug."

    assert [
             {%Popup{fixed_width: 40, fixed_height: 12}, %Rect{width: 44, height: 16}}
           ] = ScreenUI.help_popup_widgets(%{width: 44, height: 16}, state, "Guide", ["Line 1"])
  end

  test "status_text adds a moving pending indicator for active chat submits" do
    state =
      Model.new([])
      |> Map.put(:status_line, "Submitting chat message... op=room_submit-1")
      |> Map.put(:pending_room_submit, %{room_id: "room-1", text: "hello", operation_id: "room_submit-1"})

    first = ScreenUI.status_text(state, 0)
    second = ScreenUI.status_text(state, 500)

    assert first =~ "Submitting chat message... op=room_submit-1"
    assert first =~ "["
    assert first =~ "]"
    assert second =~ "Submitting chat message... op=room_submit-1"
    refute first == second
  end

  test "status_text default arity changes as the animation tick advances" do
    first =
      Model.new([])
      |> Map.put(:status_line, "Submitting chat message... op=room_submit-1")
      |> Map.put(:pending_room_submit, %{room_id: "room-1", text: "hello", operation_id: "room_submit-1"})
      |> Map.put(:status_animation_tick, 0)
      |> ScreenUI.status_text()

    second =
      Model.new([])
      |> Map.put(:status_line, "Submitting chat message... op=room_submit-1")
      |> Map.put(:pending_room_submit, %{room_id: "room-1", text: "hello", operation_id: "room_submit-1"})
      |> Map.put(:status_animation_tick, 1)
      |> ScreenUI.status_text()

    refute first == second
  end
end
