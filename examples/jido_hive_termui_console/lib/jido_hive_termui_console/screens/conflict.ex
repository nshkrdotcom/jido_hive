defmodule JidoHiveTermuiConsole.Screens.Conflict do
  @moduledoc false

  import TermUI.Component.Helpers

  alias JidoHiveTermuiConsole.{Model, Projection}
  alias TermUI.Event
  alias TermUI.Renderer.Style

  @spec event_to_msg(Event.t(), Model.t()) :: term() | nil
  def event_to_msg(%Event.Key{key: :enter}, _state), do: :submit_conflict_resolution
  def event_to_msg(%Event.Key{key: :backspace}, _state), do: :conflict_backspace
  def event_to_msg(%Event.Key{key: :escape}, _state), do: :cancel_conflict

  def event_to_msg(%Event.Key{char: "q", modifiers: modifiers}, _state) when is_list(modifiers) do
    if Enum.member?(modifiers, :ctrl), do: :quit, else: nil
  end

  def event_to_msg(%Event.Key{char: "a"}, _state), do: {:prefill_conflict, :left}
  def event_to_msg(%Event.Key{char: "b"}, _state), do: {:prefill_conflict, :right}
  def event_to_msg(%Event.Key{char: "s"}, _state), do: :dispatch_ai_synthesis

  def event_to_msg(%Event.Key{char: char}, _state) when is_binary(char) and char != "",
    do: {:conflict_append, char}

  def event_to_msg(_event, _state), do: nil

  @spec render(Model.t()) :: term()
  def render(%Model{} = state) do
    {left_lines, right_lines} =
      Projection.conflict_sides(state.conflict_left || %{}, state.conflict_right || %{})

    pane_width = max(div(state.screen_width - 6, 2), 32)

    stack(:vertical, [
      text("CONFLICT RESOLUTION", header_style()),
      stack(:horizontal, [
        render_pane(left_lines, pane_width),
        render_pane(right_lines, pane_width)
      ]),
      render_pane(
        [
          "Your resolution — authority: #{String.upcase(state.authority_level)}",
          "> " <> state.conflict_input_buf,
          "",
          "(a) accept left  ·  (b) accept right  ·  (s) dispatch AI synthesis",
          "Enter to submit  ·  ESC to cancel"
        ],
        max(state.screen_width - 2, 40)
      ),
      text(state.status_line, status_style(state))
    ])
  end

  defp render_pane(lines, width) do
    box(Enum.map(lines, &text/1), width: width, height: 14)
  end

  defp header_style, do: Style.new(fg: :cyan, attrs: [:bold])
  defp status_style(%{status_severity: :error}), do: Style.new(fg: :red, attrs: [:bold])
  defp status_style(%{status_severity: :warn}), do: Style.new(fg: :yellow)
  defp status_style(_state), do: Style.new(fg: :yellow)
end
