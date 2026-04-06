defmodule JidoHiveTermuiConsole.App do
  @moduledoc false

  use TermUI.Elm

  alias JidoHiveTermuiConsole.{Model, Projection}
  alias TermUI.{Command, Event}
  alias TermUI.Renderer.Style

  @pane_height 18

  @impl true
  def init(opts) do
    embedded_module = Keyword.get(opts, :embedded_module, JidoHiveClient.Embedded)
    embedded = Keyword.fetch!(opts, :embedded)
    snapshot = embedded_module.snapshot(embedded)

    state =
      Model.new(
        opts
        |> Keyword.put(:embedded_module, embedded_module)
        |> Keyword.put(:snapshot, snapshot)
      )

    {state, [Command.timer(0, :poll)]}
  end

  @impl true
  def event_to_msg(%Event.Resize{width: width, height: height}, _state) do
    {:msg, {:resize, width, height}}
  end

  def event_to_msg(%Event.Key{} = event, _state) do
    case shortcut_msg(event) || navigation_msg(event) || input_msg(event) do
      nil -> :ignore
      msg -> {:msg, msg}
    end
  end

  def event_to_msg(_event, _state), do: :ignore

  @impl true
  def update(:quit, state), do: {state, [:quit]}

  def update({:resize, width, height}, state) do
    {Model.resize(state, width, height), []}
  end

  def update(:poll, state) do
    {refresh_snapshot(state), [Command.timer(state.poll_interval_ms, :poll)]}
  end

  def update(:refresh, state) do
    {refresh_snapshot(state) |> Model.set_status("Refreshed"), []}
  end

  def update({:input_append, char}, state) do
    {Model.append_input(state, char), []}
  end

  def update(:input_backspace, state) do
    {Model.backspace(state), []}
  end

  def update(:select_prev, state) do
    {Model.move_selection(state, -1), []}
  end

  def update(:select_next, state) do
    {Model.move_selection(state, 1), []}
  end

  def update(:submit_input, state) do
    case String.trim(state.input_buffer) do
      "" ->
        {Model.set_status(state, "Type a message before submitting"), []}

      text ->
        selected_context_id =
          case Model.selected_context(state) do
            nil ->
              nil

            context_object ->
              Map.get(context_object, "context_id") || Map.get(context_object, :context_id)
          end

        case state.embedded_module.submit_chat(state.embedded, %{
               text: text,
               selected_context_id: selected_context_id
             }) do
          {:ok, _contribution} ->
            next_state =
              state
              |> Model.clear_input()
              |> refresh_snapshot()
              |> Model.set_status("Submitted chat message")

            {next_state, []}

          {:error, reason} ->
            {Model.set_status(state, "Submit failed: #{inspect(reason)}"), []}
        end
    end
  end

  def update(:accept_selected, state) do
    case Model.selected_context(state) do
      nil ->
        {Model.set_status(state, "No context object selected"), []}

      context_object ->
        context_id = Map.get(context_object, "context_id") || Map.get(context_object, :context_id)

        case state.embedded_module.accept_context(state.embedded, context_id, %{}) do
          {:ok, _contribution} ->
            next_state =
              state
              |> refresh_snapshot()
              |> Model.set_status("Accepted selected context object")

            {next_state, []}

          {:error, reason} ->
            {Model.set_status(state, "Accept failed: #{inspect(reason)}"), []}
        end
    end
  end

  def update(_message, state), do: {state, []}

  @impl true
  def view(state) do
    pane_width = max(div(state.screen_width - 6, 2), 44)
    input_width = max(state.screen_width - 4, 88)

    stack(:vertical, [
      text("Jido Hive TermUI Console", Style.new(fg: :cyan, attrs: [:bold])),
      text(
        "Room #{state.room_id} | #{state.participant_id} (#{state.participant_role})",
        Style.new(fg: :bright_black)
      ),
      text("", nil),
      stack(:horizontal, [
        render_pane("Conversation", Projection.conversation_lines(state.snapshot), pane_width),
        render_pane(
          "Context",
          Projection.context_lines(state.snapshot, state.selected_context_index),
          pane_width
        )
      ]),
      text("", nil),
      render_pane("Input", ["> " <> state.input_buffer], input_width, 3),
      text(state.status_line, Style.new(fg: :yellow)),
      text(
        "Enter submit | Up/Down select | Ctrl+A accept | Ctrl+R refresh | Ctrl+Q quit",
        Style.new(fg: :bright_black)
      )
    ])
  end

  defp refresh_snapshot(state) do
    snapshot = state.embedded_module.snapshot(state.embedded)
    Model.apply_snapshot(state, snapshot)
  end

  defp shortcut_msg(%Event.Key{char: char, modifiers: modifiers})
       when is_binary(char) and is_list(modifiers) do
    if Enum.member?(modifiers, :ctrl) do
      case char do
        "q" -> :quit
        "a" -> :accept_selected
        "r" -> :refresh
        _other -> nil
      end
    end
  end

  defp shortcut_msg(_event), do: nil

  defp navigation_msg(%Event.Key{key: :enter}), do: :submit_input
  defp navigation_msg(%Event.Key{key: :backspace}), do: :input_backspace
  defp navigation_msg(%Event.Key{key: :up}), do: :select_prev
  defp navigation_msg(%Event.Key{key: :down}), do: :select_next
  defp navigation_msg(_event), do: nil

  defp input_msg(%Event.Key{char: char}) when is_binary(char) and char != "",
    do: {:input_append, char}

  defp input_msg(_event), do: nil

  defp render_pane(title, lines, width, height \\ @pane_height) do
    heading = Style.new(fg: :green, attrs: [:bold])
    divider = Style.new(fg: :bright_black)

    content =
      [
        text(title, heading),
        text(String.duplicate("─", max(width - 2, 10)), divider)
      ] ++ Enum.map(lines, &text(&1, nil))

    box(content, width: width, height: height)
  end
end
