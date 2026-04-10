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

  test "help popup wraps and scrolls overflowed guide copy" do
    state = Model.new([]) |> Map.put(:help_visible, true) |> Map.put(:help_scroll, 3)

    lines =
      List.duplicate(
        "This help line is intentionally long so the popup has to wrap it before measuring height.",
        12
      )

    assert ScreenUI.help_popup_max_scroll(%{width: 72, height: 16}, lines) > 3

    assert [
             {%Popup{
                fixed_width: 68,
                fixed_height: 12,
                content: %Paragraph{text: text, wrap: false, scroll: {3, 0}}
              }, %Rect{width: 72, height: 16}}
           ] = ScreenUI.help_popup_widgets(%{width: 72, height: 16}, state, "Guide", lines)

    assert text =~ "PageUp/PageDown scroll"
  end

  test "status_text adds a moving pending indicator for active chat submits" do
    state =
      Model.new([])
      |> Map.put(:status_line, "Submitting chat message... op=room_submit-1")
      |> Map.put(:pending_room_submit, %{
        room_id: "room-1",
        text: "hello",
        operation_id: "room_submit-1"
      })

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
      |> Map.put(:pending_room_submit, %{
        room_id: "room-1",
        text: "hello",
        operation_id: "room_submit-1"
      })
      |> Map.put(:status_animation_tick, 0)
      |> ScreenUI.status_text()

    second =
      Model.new([])
      |> Map.put(:status_line, "Submitting chat message... op=room_submit-1")
      |> Map.put(:pending_room_submit, %{
        room_id: "room-1",
        text: "hello",
        operation_id: "room_submit-1"
      })
      |> Map.put(:status_animation_tick, 1)
      |> ScreenUI.status_text()

    refute first == second
  end

  test "debug popup includes runtime snapshot details when available" do
    state =
      Model.new([])
      |> Map.put(:debug_visible, true)
      |> Map.put(:runtime_snapshot, %{
        mode: :reducer,
        render_count: 7,
        active_async_commands: 1,
        trace_enabled?: true,
        trace_events: [%{kind: :message, details: %{source: :info}}],
        subscription_count: 1,
        subscriptions: [%{id: :poll, kind: :interval, interval_ms: 1_000, active?: true}]
      })

    assert [
             {%Popup{content: %Paragraph{text: text}}, %Rect{width: 120, height: 24}}
           ] = ScreenUI.help_popup_widgets(%{width: 120, height: 24}, state, "Guide", [])

    assert text =~ "Runtime: mode=reducer renders=7 async=1"
    assert text =~ "Runtime trace: enabled=true events=1"
    assert text =~ "sub poll: interval 1000ms active=true"
    assert text =~ "trace message: source=info"
  end
end
