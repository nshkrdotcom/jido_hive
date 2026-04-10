defmodule JidoHiveConsole.Screens.Room do
  @moduledoc false

  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Paragraph, Textarea}
  alias JidoHiveConsole.{HelpGuide, InputKey, Model, Projection, ScreenUI}

  @spec event_to_msg(Event.t(), Model.t()) :: term() | nil
  def event_to_msg(%Event.Key{code: "up"}, _state), do: :select_prev
  def event_to_msg(%Event.Key{code: "down"}, _state), do: :select_next
  def event_to_msg(%Event.Key{code: "enter"}, _state), do: :room_enter
  def event_to_msg(%Event.Key{code: "tab"}, _state), do: :cycle_pane_focus
  def event_to_msg(%Event.Key{code: "esc"}, _state), do: :room_escape

  def event_to_msg(%Event.Key{code: "j", modifiers: ["ctrl"]}, _state),
    do: {:room_input_key, "enter", []}

  def event_to_msg(%Event.Key{code: code, modifiers: modifiers}, _state)
      when is_binary(code) and modifiers == ["ctrl"] do
    ctrl_shortcut(code)
  end

  def event_to_msg(%Event.Key{} = event, _state) do
    case InputKey.text_input_key(event) do
      {:ok, code} -> {:room_input_key, code}
      :error -> nil
    end
  end

  def event_to_msg(_event, _state), do: nil

  @spec render(Model.t(), %{width: pos_integer(), height: pos_integer()}) :: [{term(), term()}]
  def render(%Model{} = state, frame) do
    area = ScreenUI.root_area(frame)

    [header_area, workflow_area, main_area, input_area, footer_area, status_area] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:length, 10},
        {:min, 10},
        {:length, 5},
        {:length, 2},
        {:length, 1}
      ])

    widgets =
      [
        {header_widget(state), header_area},
        {workflow_widget(state), workflow_area}
      ] ++
        main_widgets(state, main_area) ++
        [
          {input_widget(state), input_area},
          {footer_widget(state), footer_area},
          {status_widget(state), status_area}
        ]

    widgets ++
      ScreenUI.help_popup_widgets(frame, state, HelpGuide.title(state), HelpGuide.lines(state))
  end

  defp main_widgets(state, area) when area.width < 88 do
    [conversation_area, context_area, detail_area, events_area] =
      Layout.split(area, :vertical, [{:percentage, 32}, {:min, 8}, {:min, 8}, {:length, 6}])

    [
      {conversation_widget(state, conversation_area), conversation_area},
      {context_widget(state, context_area), context_area},
      {detail_widget(state, detail_area), detail_area},
      {events_widget(state, events_area), events_area}
    ]
  end

  defp main_widgets(state, area) do
    [left_area, center_area, right_area] =
      Layout.split(area, :horizontal, [{:percentage, 34}, {:percentage, 28}, {:percentage, 38}])

    [conversation_area, events_area] =
      Layout.split(left_area, :vertical, [{:min, 8}, {:length, 7}])

    [
      {conversation_widget(state, conversation_area), conversation_area},
      {events_widget(state, events_area), events_area},
      {context_widget(state, center_area), center_area},
      {detail_widget(state, right_area), right_area}
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

  defp workflow_widget(state) do
    summary = Projection.workflow_summary(state.snapshot)

    lines =
      [
        "Objective: #{summary.objective}",
        "Stage: #{summary.stage}",
        "Next action: #{summary.next_action}",
        "Why: #{summary.reason}",
        "Graph: #{summary.graph_counts}",
        "Publish: #{summary.publish_state}",
        "Focus queue"
      ] ++
        workflow_focus_lines(summary.focus_queue) ++
        [
          "Selected: #{selected_context_label(state)}  ·  Compose as: #{compose_mode_label(state.relation_mode)}  ·  Focus: #{state.pane_focus}"
        ]

    ScreenUI.pane("Workflow", lines, border_fg: :cyan, wrap: true)
  end

  defp conversation_widget(state, area) do
    ScreenUI.pane(
      "Conversation",
      Projection.conversation_lines(state.snapshot,
        limit: max(area.height * 3, 12),
        participant_id: state.participant_id,
        pending_submit: state.pending_room_submit
      ),
      border_fg: :cyan,
      wrap: true
    )
  end

  defp context_widget(state, area) do
    width = max(area.width - 4, 20)
    lines = active_lines(state, width, max(area.height * 3, 16))
    ScreenUI.pane(context_title(state), lines, border_fg: :yellow, wrap: true)
  end

  defp detail_widget(state, area) do
    width = max(area.width - 4, 20)
    lines = detail_lines(state, width, max(area.height * 3, 16))
    ScreenUI.pane(detail_title(state), lines, border_fg: :green, wrap: true)
  end

  defp events_widget(state, area) do
    ScreenUI.pane(
      "Events",
      Projection.event_log_display(state.event_log_lines, max(area.height * 2, 8)),
      border_fg: :green,
      wrap: true
    )
  end

  defp input_widget(%Model{room_input_ref: ref}) when is_reference(ref) do
    %Textarea{
      state: ref,
      style: %Style{fg: :white},
      cursor_style: %Style{fg: :black, bg: :white},
      cursor_line_style: %Style{bg: :dark_gray},
      placeholder:
        "Write guidance, clarification, or a decision draft.\nCtrl+J inserts newline. Enter sends.",
      placeholder_style: ScreenUI.meta_style(),
      block: %ExRatatui.Widgets.Block{
        title: "Compose Steering Message",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :yellow},
        padding: {1, 1, 0, 0}
      }
    }
  end

  defp input_widget(%Model{} = state) do
    ScreenUI.pane(
      "Compose Steering Message",
      String.split(state.input_buffer, "\n"),
      border_fg: :yellow,
      wrap: true
    )
  end

  defp footer_widget(state) do
    ScreenUI.text_widget(
      "Enter send/open conflict  ·  Ctrl+J newline  ·  Ctrl+E provenance  ·  Ctrl+A accept  ·  Ctrl+R refresh  ·  Ctrl+P publish  ·  Ctrl+B back  ·  Ctrl+G help  ·  F2 debug  ·  Ctrl+Q quit  ·  Compose #{compose_mode_label(state.relation_mode)}",
      style: ScreenUI.meta_style(),
      wrap: true
    )
  end

  defp status_widget(state) do
    ScreenUI.text_widget(ScreenUI.status_text(state),
      style: ScreenUI.status_style(state),
      wrap: false
    )
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

  defp context_title(%{drill_context_id: nil}), do: "Shared Graph"

  defp context_title(%{drill_context_id: drill_context_id}),
    do: "Shared Graph: PROVENANCE #{drill_context_id}"

  defp detail_title(%{drill_context_id: nil}), do: "Selected Review"

  defp detail_title(%{drill_context_id: drill_context_id}),
    do: "Selected Review: PROVENANCE #{drill_context_id}"

  defp selected_context_label(state) do
    case Model.selected_context(state) do
      nil -> "none"
      object -> Map.get(object, "context_id") || Map.get(object, :context_id) || "none"
    end
  end

  defp detail_lines(state, width, limit) do
    lines =
      if state.drill_context_id do
        state.provenance_lines
      else
        Projection.selected_context_detail_lines(Model.selected_context(state), state.snapshot)
      end

    lines
    |> Enum.map(&Projection.truncate(&1, width))
    |> Enum.take(limit)
  end

  defp compose_mode_label(:none), do: "plain chat"
  defp compose_mode_label(:contextual), do: "contextual note"
  defp compose_mode_label(:references), do: "reference"
  defp compose_mode_label(:derives_from), do: "derives from"
  defp compose_mode_label(:supports), do: "support"
  defp compose_mode_label(:contradicts), do: "contradiction"
  defp compose_mode_label(:resolves), do: "resolution"
  defp compose_mode_label(other), do: Atom.to_string(other)

  defp workflow_focus_lines([]), do: ["- no immediate focus items"]
  defp workflow_focus_lines(lines), do: Enum.map(lines, &("- " <> &1))

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
