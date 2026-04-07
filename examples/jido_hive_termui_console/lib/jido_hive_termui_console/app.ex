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

  def update({:set_relation_mode, mode}, state) do
    next_state =
      state
      |> Model.set_relation_mode(mode)
      |> Model.set_status("Compose mode: #{relation_mode_label(mode)}")

    {next_state, []}
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
        selected_context = Model.selected_context(state)

        case state.embedded_module.submit_chat(
               state.embedded,
               submit_attrs(text, selected_context, state.relation_mode)
             ) do
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
      text(
        "Mode #{relation_mode_label(state.relation_mode)} | Selected #{selected_context_label(state)}",
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
        "Enter submit | Up/Down select | Ctrl+A accept | Ctrl+T contextual | Ctrl+F ref | Ctrl+D derive | Ctrl+S support | Ctrl+X contradict | Ctrl+N none | Ctrl+R refresh | Ctrl+Q quit",
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
      ctrl_shortcut_msg(char)
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

  defp submit_attrs(text, _selected_context, :none), do: %{text: text}
  defp submit_attrs(text, nil, _mode), do: %{text: text}

  defp submit_attrs(text, selected_context, mode) do
    %{
      text: text,
      selected_context_id: context_id(selected_context),
      selected_context_object_type: context_object_type(selected_context),
      selected_relation: Atom.to_string(mode)
    }
  end

  defp relation_mode_label(mode) do
    mode
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp selected_context_label(state) do
    case Model.selected_context(state) do
      nil -> "none"
      context_object -> context_id(context_object) || "none"
    end
  end

  defp context_id(context_object),
    do: Map.get(context_object, "context_id") || Map.get(context_object, :context_id)

  defp context_object_type(context_object) do
    Map.get(context_object, "object_type") || Map.get(context_object, :object_type)
  end

  defp ctrl_shortcut_msg("q"), do: :quit
  defp ctrl_shortcut_msg("a"), do: :accept_selected
  defp ctrl_shortcut_msg("r"), do: :refresh

  defp ctrl_shortcut_msg(char) do
    case relation_mode_shortcut(char) do
      nil -> nil
      mode -> {:set_relation_mode, mode}
    end
  end

  defp relation_mode_shortcut("t"), do: :contextual
  defp relation_mode_shortcut("f"), do: :references
  defp relation_mode_shortcut("d"), do: :derives_from
  defp relation_mode_shortcut("s"), do: :supports
  defp relation_mode_shortcut("x"), do: :contradicts
  defp relation_mode_shortcut("n"), do: :none
  defp relation_mode_shortcut(_char), do: nil
end
