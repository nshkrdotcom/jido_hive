defmodule JidoHiveTermuiConsole.Screens.Room do
  @moduledoc false

  import TermUI.Component.Helpers

  alias JidoHiveTermuiConsole.{Model, Projection}
  alias TermUI.Event
  alias TermUI.Renderer.Style

  @pane_height 12

  @spec event_to_msg(Event.t(), Model.t()) :: term() | nil
  def event_to_msg(%Event.Key{key: :up}, _state), do: :select_prev
  def event_to_msg(%Event.Key{key: :down}, _state), do: :select_next
  def event_to_msg(%Event.Key{key: :enter}, _state), do: :room_enter
  def event_to_msg(%Event.Key{key: :tab}, _state), do: :cycle_pane_focus
  def event_to_msg(%Event.Key{key: :backspace}, _state), do: :input_backspace
  def event_to_msg(%Event.Key{key: :escape}, _state), do: :room_escape

  def event_to_msg(%Event.Key{char: char, modifiers: modifiers}, _state)
      when is_binary(char) and char != "" and is_list(modifiers) do
    if Enum.member?(modifiers, :ctrl) do
      ctrl_shortcut(char)
    else
      {:input_append, char}
    end
  end

  def event_to_msg(_event, _state), do: nil

  @spec render(Model.t()) :: term()
  def render(%Model{} = state) do
    status = Map.get(state.snapshot, "status", "idle")
    dispatch = Map.get(state.snapshot, "dispatch_state", %{})

    slots =
      "#{Map.get(dispatch, "completed_slots", 0)}/#{Map.get(dispatch, "total_slots", 0)} slots"

    header =
      "Room #{state.room_id}  ·  #{state.participant_id} (#{String.upcase(state.authority_level)})  ·  #{status}  ·  #{slots}" <>
        if(state.sync_error, do: "  ·  ⚠ sync error", else: "")

    stale_count = Enum.count(Map.get(state.snapshot, "context_objects", []), &stale?/1)

    conflict_count =
      Enum.count(Map.get(state.snapshot, "context_objects", []), &Projection.conflict?/1)

    selected = selected_context_label(state)

    mode_line =
      "Mode: #{Atom.to_string(state.relation_mode)}  ·  Selected: #{selected}  ·  [STALE:#{stale_count}] [CONFLICT:#{conflict_count}]"

    context_lines =
      if state.drill_context_id do
        state.provenance_lines
      else
        Projection.context_lines(state.snapshot, state.selected_context_index,
          width: pane_content_width(state)
        )
      end

    conversation_lines = Projection.conversation_lines(state.snapshot, limit: @pane_height - 2)
    event_lines = Projection.event_log_display(state.event_log_lines, 4)
    input_line = ["> " <> state.input_buffer]

    panes =
      cond do
        state.screen_width < 88 ->
          active_lines =
            case state.pane_focus do
              :conversation -> conversation_lines
              _other -> context_lines
            end

          [
            render_pane(
              active_title(state),
              active_lines,
              max(state.screen_width - 2, 40),
              @pane_height
            )
          ]

        state.screen_width < 140 ->
          pane_width = max(div(state.screen_width - 6, 2), 36)

          [
            stack(:horizontal, [
              render_pane("Conversation", conversation_lines, pane_width, @pane_height),
              render_pane(context_title(state), context_lines, pane_width, @pane_height)
            ]),
            render_pane("Events (polling)", event_lines, max(state.screen_width - 2, 40), 6)
          ]

        true ->
          pane_width = max(div(state.screen_width - 10, 3), 28)

          [
            stack(:horizontal, [
              render_pane("Conversation", conversation_lines, pane_width, @pane_height),
              render_pane(context_title(state), context_lines, pane_width, @pane_height),
              render_pane("Events (polling)", event_lines, pane_width, @pane_height)
            ])
          ]
      end

    stack(:vertical, [
      text(header, header_style()),
      text(mode_line, meta_style()),
      stack(:vertical, panes),
      render_pane("Input", input_line, max(state.screen_width - 2, 40), 3),
      text(help_line(state), meta_style()),
      text(state.status_line, status_style(state))
    ])
  end

  defp render_pane(title, lines, width, height) do
    children = [text(title, pane_title_style()) | Enum.map(lines, &text/1)]
    box(children, width: width, height: height)
  end

  defp pane_content_width(state) do
    max(div(state.screen_width - 6, 2) - 4, 28)
  end

  defp active_title(%{pane_focus: :conversation}), do: "Conversation"
  defp active_title(state), do: context_title(state)
  defp context_title(%{drill_context_id: nil}), do: "Context"

  defp context_title(%{drill_context_id: drill_context_id}),
    do: "Context: PROVENANCE #{drill_context_id}"

  defp selected_context_label(state) do
    case Model.selected_context(state) do
      nil -> "none"
      object -> Map.get(object, "context_id") || Map.get(object, :context_id) || "none"
    end
  end

  defp help_line(_state) do
    "Enter submit/open conflict  ·  Ctrl+E provenance  ·  Ctrl+A accept  ·  Ctrl+P publish  ·  Ctrl+B back  ·  Ctrl+V resolves  ·  Tab focus  ·  Ctrl+Q quit"
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

  defp header_style, do: Style.new(fg: :cyan, attrs: [:bold])
  defp pane_title_style, do: Style.new(fg: :green, attrs: [:bold])
  defp meta_style, do: Style.new(fg: :bright_black)
  defp status_style(%{status_severity: :error}), do: Style.new(fg: :red, attrs: [:bold])
  defp status_style(%{status_severity: :warn}), do: Style.new(fg: :yellow)
  defp status_style(_state), do: Style.new(fg: :yellow)
end
