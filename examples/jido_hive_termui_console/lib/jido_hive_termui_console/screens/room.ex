defmodule JidoHiveTermuiConsole.Screens.Room do
  @moduledoc false

  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Paragraph, TextInput}
  alias JidoHiveTermuiConsole.{Model, Projection, ScreenUI}

  @input_keys ["backspace", "delete", "left", "right", "home", "end"]

  @spec event_to_msg(Event.t(), Model.t()) :: term() | nil
  def event_to_msg(%Event.Key{code: "up"}, _state), do: :select_prev
  def event_to_msg(%Event.Key{code: "down"}, _state), do: :select_next
  def event_to_msg(%Event.Key{code: "enter"}, _state), do: :room_enter
  def event_to_msg(%Event.Key{code: "tab"}, _state), do: :cycle_pane_focus
  def event_to_msg(%Event.Key{code: "esc"}, _state), do: :room_escape

  def event_to_msg(%Event.Key{code: code, modifiers: modifiers}, _state)
      when is_binary(code) and modifiers == ["ctrl"] do
    ctrl_shortcut(code)
  end

  def event_to_msg(%Event.Key{code: code, modifiers: []}, _state) when code in @input_keys,
    do: {:room_input_key, code}

  def event_to_msg(%Event.Key{code: code, modifiers: []}, _state)
      when is_binary(code) and byte_size(code) > 0 do
    {:room_input_key, code}
  end

  def event_to_msg(_event, _state), do: nil

  @spec render(Model.t(), %{width: pos_integer(), height: pos_integer()}) :: [{term(), term()}]
  def render(%Model{} = state, frame) do
    area = ScreenUI.root_area(frame)

    [header_area, meta_area, main_area, input_area, footer_area, status_area] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:length, 1},
        {:min, 10},
        {:length, 3},
        {:length, 2},
        {:length, 1}
      ])

    widgets =
      [
        {header_widget(state), header_area},
        {meta_widget(state), meta_area}
      ] ++
        main_widgets(state, main_area) ++
        [
          {input_widget(state), input_area},
          {footer_widget(state), footer_area},
          {status_widget(state), status_area}
        ]

    widgets ++ ScreenUI.help_popup_widgets(frame, state, "Room Guide", help_lines(state))
  end

  defp main_widgets(state, area) when area.width < 88 do
    [conversation_area, context_area, events_area] =
      Layout.split(area, :vertical, [{:percentage, 35}, {:min, 8}, {:length, 6}])

    [
      {conversation_widget(state, conversation_area), conversation_area},
      {context_widget(state, context_area), context_area},
      {events_widget(state, events_area), events_area}
    ]
  end

  defp main_widgets(state, area) do
    [left_area, right_area] =
      Layout.split(area, :horizontal, [{:percentage, 42}, {:percentage, 58}])

    [conversation_area, events_area] =
      Layout.split(left_area, :vertical, [{:min, 8}, {:length, 7}])

    [
      {conversation_widget(state, conversation_area), conversation_area},
      {events_widget(state, events_area), events_area},
      {context_widget(state, right_area), right_area}
    ]
  end

  defp header_widget(state) do
    status = Map.get(state.snapshot, "status", "idle")
    dispatch = Map.get(state.snapshot, "dispatch_state", %{})

    slots =
      "#{Map.get(dispatch, "completed_slots", 0)}/#{Map.get(dispatch, "total_slots", 0)} slots"

    text =
      "Room #{state.room_id}  ·  #{state.participant_id} (#{String.upcase(state.authority_level)})  ·  #{status}  ·  #{slots}" <>
        if(state.sync_error, do: "  ·  ⚠ sync error", else: "")

    %Paragraph{
      text: text,
      wrap: false,
      style: ScreenUI.header_style(),
      block: %ExRatatui.Widgets.Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan},
        padding: {1, 1, 0, 0}
      }
    }
  end

  defp meta_widget(state) do
    stale_count = Enum.count(Map.get(state.snapshot, "context_objects", []), &stale?/1)

    conflict_count =
      Enum.count(Map.get(state.snapshot, "context_objects", []), &Projection.conflict?/1)

    text =
      "Mode: #{Atom.to_string(state.relation_mode)}  ·  Selected: #{selected_context_label(state)}  ·  [STALE:#{stale_count}] [CONFLICT:#{conflict_count}]  ·  Focus: #{state.pane_focus}"

    ScreenUI.text_widget(text, style: ScreenUI.meta_style(), wrap: false)
  end

  defp conversation_widget(state, area) do
    ScreenUI.pane(
      "Conversation",
      Projection.conversation_lines(state.snapshot, limit: max(area.height * 3, 12)),
      border_fg: :cyan,
      wrap: true
    )
  end

  defp context_widget(state, area) do
    width = max(area.width - 4, 20)
    lines = active_lines(state, width, max(area.height * 3, 16))
    ScreenUI.pane(context_title(state), lines, border_fg: :yellow, wrap: true)
  end

  defp events_widget(state, area) do
    ScreenUI.pane(
      "Events (polling)",
      Projection.event_log_display(state.event_log_lines, max(area.height * 2, 8)),
      border_fg: :green,
      wrap: true
    )
  end

  defp input_widget(%Model{room_input_ref: ref}) when is_reference(ref) do
    %TextInput{
      state: ref,
      style: %Style{fg: :white},
      cursor_style: %Style{fg: :black, bg: :white},
      placeholder: "Type a room message...",
      placeholder_style: ScreenUI.meta_style(),
      block: %ExRatatui.Widgets.Block{
        title: "Draft",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :yellow},
        padding: {1, 1, 0, 0}
      }
    }
  end

  defp input_widget(%Model{} = state) do
    ScreenUI.pane(
      "Draft",
      ["> " <> state.input_buffer],
      border_fg: :yellow,
      wrap: false
    )
  end

  defp footer_widget(state) do
    ScreenUI.text_widget(
      "Type to edit draft  ·  Enter submit/open conflict  ·  Ctrl+E provenance  ·  Ctrl+A accept  ·  Ctrl+P publish  ·  Ctrl+B back  ·  Ctrl+Q quit  ·  Mode #{Atom.to_string(state.relation_mode)}",
      style: ScreenUI.meta_style(),
      wrap: true
    )
  end

  defp status_widget(state) do
    ScreenUI.text_widget(state.status_line, style: ScreenUI.status_style(state), wrap: false)
  end

  defp active_lines(state, width, limit) do
    if state.drill_context_id do
      Enum.take(state.provenance_lines, limit)
    else
      Projection.context_lines(state.snapshot, state.selected_context_index,
        width: width,
        limit: limit
      )
    end
  end

  defp context_title(%{drill_context_id: nil}), do: "Context"

  defp context_title(%{drill_context_id: drill_context_id}),
    do: "Context: PROVENANCE #{drill_context_id}"

  defp selected_context_label(state) do
    case Model.selected_context(state) do
      nil -> "none"
      object -> Map.get(object, "context_id") || Map.get(object, :context_id) || "none"
    end
  end

  defp help_lines(state) do
    [
      "This is the room workspace.",
      "Conversation shows recent contributions. Context shows the selected room knowledge. Events shows recent runtime activity.",
      "Type directly in the draft box at the bottom. Plain letters, including q, edit the draft. Only Ctrl+Q quits.",
      "Press Enter to send the current draft.",
      "If the draft is empty and the selected item is a contradiction, Enter opens conflict resolution.",
      "Use Up and Down to move the selected context item.",
      "Ctrl+N switches to plain chat. Ctrl+T contextual. Ctrl+F references. Ctrl+D derives_from. Ctrl+S supports. Ctrl+X contradicts. Ctrl+V resolves.",
      "Ctrl+E opens provenance for the selected context. Ctrl+A accepts the selected item. Ctrl+P opens publish. Ctrl+B returns to the lobby.",
      "Current draft mode is #{Atom.to_string(state.relation_mode)} and the selected context is #{selected_context_label(state)}."
    ]
  end

  defp stale?(object) do
    derived = Map.get(object, "derived") || %{}
    Map.get(derived, "stale_ancestor", false)
  end

  defp ctrl_shortcut("q"), do: :quit
  defp ctrl_shortcut("a"), do: :accept_selected
  defp ctrl_shortcut("b"), do: :back_to_lobby
  defp ctrl_shortcut("e"), do: :toggle_drill
  defp ctrl_shortcut("p"), do: :open_publish
  defp ctrl_shortcut("r"), do: :refresh_room
  defp ctrl_shortcut("t"), do: {:set_relation_mode, :contextual}
  defp ctrl_shortcut("f"), do: {:set_relation_mode, :references}
  defp ctrl_shortcut("d"), do: {:set_relation_mode, :derives_from}
  defp ctrl_shortcut("s"), do: {:set_relation_mode, :supports}
  defp ctrl_shortcut("x"), do: {:set_relation_mode, :contradicts}
  defp ctrl_shortcut("v"), do: {:set_relation_mode, :resolves}
  defp ctrl_shortcut("n"), do: {:set_relation_mode, :none}
  defp ctrl_shortcut(_char), do: nil
end
