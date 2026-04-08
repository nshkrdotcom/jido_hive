defmodule JidoHiveTermuiConsole.Screens.Conflict do
  @moduledoc false

  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Paragraph, TextInput}
  alias JidoHiveTermuiConsole.{InputKey, Model, Projection, ScreenUI}

  @spec event_to_msg(Event.t(), Model.t()) :: term() | nil
  def event_to_msg(%Event.Key{code: "enter"}, _state), do: :submit_conflict_resolution
  def event_to_msg(%Event.Key{code: "esc"}, _state), do: :cancel_conflict
  def event_to_msg(%Event.Key{code: "q", modifiers: ["ctrl"]}, _state), do: :quit
  def event_to_msg(%Event.Key{code: "a"}, _state), do: {:prefill_conflict, :left}
  def event_to_msg(%Event.Key{code: "b"}, _state), do: {:prefill_conflict, :right}
  def event_to_msg(%Event.Key{code: "s"}, _state), do: :dispatch_ai_synthesis

  def event_to_msg(%Event.Key{} = event, _state) do
    case InputKey.text_input_key(event) do
      {:ok, code} -> {:conflict_input_key, code}
      :error -> nil
    end
  end

  def event_to_msg(_event, _state), do: nil

  @spec render(Model.t(), %{width: pos_integer(), height: pos_integer()}) :: [{term(), term()}]
  def render(%Model{} = state, frame) do
    area = ScreenUI.root_area(frame)

    [header_area, meta_area, body_area, input_area, footer_area, status_area] =
      Layout.split(area, :vertical, [
        {:length, 2},
        {:length, 1},
        {:min, 10},
        {:length, 3},
        {:length, 2},
        {:length, 1}
      ])

    [left_area, right_area] =
      Layout.split(body_area, :horizontal, [{:percentage, 50}, {:percentage, 50}])

    widgets = [
      {header_widget(), header_area},
      {meta_widget(), meta_area},
      {side_widget("Left Side", elem(conflict_lines(state), 0)), left_area},
      {side_widget("Right Side", elem(conflict_lines(state), 1)), right_area},
      {input_widget(state), input_area},
      {footer_widget(), footer_area},
      {status_widget(state), status_area}
    ]

    widgets ++ ScreenUI.help_popup_widgets(frame, state, "Conflict Guide", help_lines())
  end

  defp conflict_lines(state) do
    Projection.conflict_sides(state.conflict_left || %{}, state.conflict_right || %{})
  end

  defp header_widget do
    %Paragraph{
      text: "Conflict Resolution",
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

  defp meta_widget do
    ScreenUI.text_widget("Type a final decision, or use the helpers below to prefill a draft.",
      style: ScreenUI.meta_style(),
      wrap: true
    )
  end

  defp side_widget(title, lines) do
    ScreenUI.pane(title, lines, border_fg: :cyan, wrap: true)
  end

  defp input_widget(%Model{conflict_input_ref: ref} = state) when is_reference(ref) do
    %TextInput{
      state: ref,
      style: %Style{fg: :white},
      cursor_style: %Style{fg: :black, bg: :white},
      placeholder: "Write a resolving decision...",
      placeholder_style: ScreenUI.meta_style(),
      block: %ExRatatui.Widgets.Block{
        title: "Resolution Draft (#{String.upcase(state.authority_level)})",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :yellow},
        padding: {1, 1, 0, 0}
      }
    }
  end

  defp input_widget(%Model{} = state) do
    ScreenUI.pane(
      "Resolution Draft (#{String.upcase(state.authority_level)})",
      ["> " <> state.conflict_input_buf],
      border_fg: :yellow,
      wrap: false
    )
  end

  defp footer_widget do
    ScreenUI.text_widget(
      "a accept left  ·  b accept right  ·  s ask AI synthesis  ·  Enter submit  ·  Esc cancel  ·  Ctrl+Q quit",
      style: ScreenUI.meta_style(),
      wrap: true
    )
  end

  defp status_widget(state) do
    ScreenUI.text_widget(state.status_line, style: ScreenUI.status_style(state), wrap: false)
  end

  defp help_lines do
    [
      "This screen is for resolving a contradiction.",
      "Read the left and right sides, then write a decision in the draft box.",
      "Press a to prefill an accept-left decision.",
      "Press b to prefill an accept-right decision.",
      "Press s to ask the system for an AI synthesis request.",
      "Press Enter to submit the draft as a resolving decision.",
      "Press Esc to cancel and return to the room."
    ]
  end
end
