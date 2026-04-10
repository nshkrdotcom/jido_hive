defmodule JidoHiveConsole.Screens.Publish do
  @moduledoc false

  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{List, Paragraph, TextInput}
  alias JidoHiveConsole.{HelpGuide, InputKey, Model, Projection, ScreenUI}

  @spec event_to_msg(Event.t(), Model.t()) :: term() | nil
  def event_to_msg(%Event.Key{code: "tab"}, _state), do: :publish_next_focus
  def event_to_msg(%Event.Key{code: "enter"}, _state), do: :publish_submit
  def event_to_msg(%Event.Key{code: "esc"}, _state), do: :cancel_publish
  def event_to_msg(%Event.Key{code: "q", modifiers: ["ctrl"]}, _state), do: :quit

  def event_to_msg(%Event.Key{code: "r"}, state) do
    case current_focus(state) do
      %{type: :binding} -> {:publish_input_key, "r"}
      _other -> :publish_refresh_auth
    end
  end

  def event_to_msg(%Event.Key{code: " ", modifiers: []}, state) do
    case current_focus(state) do
      %{type: :binding} -> {:publish_input_key, " "}
      _other -> :publish_toggle_current
    end
  end

  def event_to_msg(%Event.Key{} = event, state) do
    case {current_focus(state), InputKey.text_input_key(event)} do
      {%{type: :binding}, {:ok, code}} -> {:publish_input_key, code}
      _other -> nil
    end
  end

  def event_to_msg(_event, _state), do: nil

  @spec render(Model.t(), %{width: pos_integer(), height: pos_integer()}) :: [{term(), term()}]
  def render(%Model{} = state, frame) do
    area = ScreenUI.root_area(frame)

    [header_area, meta_area, main_area, editor_area, footer_area, status_area] =
      Layout.split(area, :vertical, [
        {:length, 2},
        {:length, 1},
        {:min, 10},
        {:length, 4},
        {:length, 2},
        {:length, 1}
      ])

    [left_area, right_area] =
      Layout.split(main_area, :horizontal, [{:percentage, 42}, {:percentage, 58}])

    widgets = [
      {header_widget(state), header_area},
      {meta_widget(state), meta_area},
      {list_widget(state), left_area},
      {preview_widget(state), right_area},
      {editor_widget(state), editor_area},
      {footer_widget(), footer_area},
      {status_widget(state), status_area}
    ]

    widgets ++
      ScreenUI.help_popup_widgets(frame, state, HelpGuide.title(state), HelpGuide.lines(state))
  end

  @spec focus_items(Model.t()) :: [map()]
  def focus_items(%Model{} = state) do
    publication_entries(state)
    |> Enum.flat_map(fn publication ->
      channel = publication["channel"]
      bindings = publication["required_bindings"] || []

      [%{type: :channel, channel: channel}] ++
        Enum.map(bindings, fn binding ->
          %{type: :binding, channel: channel, field: binding["field"]}
        end)
    end)
  end

  @spec current_focus(Model.t()) :: map() | nil
  def current_focus(%Model{} = state), do: Enum.at(focus_items(state), state.publish_cursor)

  @spec validate_submission(Model.t()) :: :ok | {:error, String.t()}
  def validate_submission(%Model{} = state) do
    if state.publish_selected == [] do
      {:error, "Select at least one publication channel"}
    else
      validate_selected_publications(state)
    end
  end

  defp publication_entries(%Model{publish_plan: %{"publications" => publications}}),
    do: publications

  defp publication_entries(%Model{publish_plan: %{"data" => %{"publications" => publications}}}),
    do: publications

  defp publication_entries(_state), do: []

  defp header_widget(state) do
    %Paragraph{
      text: "Publish  ·  Room #{state.room_id}",
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
    ScreenUI.text_widget(
      "Selected channels: #{Enum.join(state.publish_selected, ", ") |> blank_to("none")}",
      style: ScreenUI.meta_style(),
      wrap: true
    )
  end

  defp list_widget(%Model{} = state) do
    items = publication_items(state)

    if items == [] do
      ScreenUI.pane("Channels and Bindings", ["Loading publication plan..."], border_fg: :cyan)
    else
      %List{
        items: items,
        selected: state.publish_cursor,
        highlight_symbol: "> ",
        style: %Style{fg: :white},
        highlight_style: %Style{fg: :yellow, modifiers: [:bold]},
        block: %ExRatatui.Widgets.Block{
          title: "Channels and Bindings",
          borders: [:all],
          border_type: :rounded,
          border_style: %Style{fg: :cyan},
          padding: {1, 1, 0, 0}
        }
      }
    end
  end

  defp preview_widget(state) do
    ScreenUI.pane(
      "Preview (#{current_channel(state) || "none"})",
      preview_lines(state, current_channel(state), max(state.screen_width - 10, 48)),
      border_fg: :green,
      wrap: true
    )
  end

  defp editor_widget(%Model{publish_input_ref: ref} = state) when is_reference(ref) do
    case current_focus(state) do
      %{type: :binding, channel: channel, field: field} ->
        %TextInput{
          state: ref,
          style: %Style{fg: :white},
          cursor_style: %Style{fg: :black, bg: :white},
          placeholder: binding_description(state, channel, field),
          placeholder_style: ScreenUI.meta_style(),
          block: %ExRatatui.Widgets.Block{
            title: "Edit #{channel}.#{field}",
            borders: [:all],
            border_type: :rounded,
            border_style: %Style{fg: :yellow},
            padding: {1, 1, 0, 0}
          }
        }

      _other ->
        ScreenUI.pane(
          "Editor",
          [auth_summary(state)],
          border_fg: :yellow,
          wrap: true
        )
    end
  end

  defp editor_widget(%Model{} = state) do
    ScreenUI.pane("Editor", [auth_summary(state)], border_fg: :yellow, wrap: true)
  end

  defp footer_widget do
    ScreenUI.text_widget(
      "Tab focus  ·  Space toggle channel  ·  Type binding  ·  r refresh auth on channel rows  ·  Enter publish  ·  Esc back  ·  Ctrl+G help  ·  F2 debug  ·  Ctrl+Q quit",
      style: ScreenUI.meta_style(),
      wrap: true
    )
  end

  defp status_widget(state) do
    ScreenUI.text_widget(state.status_line, style: ScreenUI.status_style(state), wrap: false)
  end

  defp publication_items(state) do
    focus = current_focus(state)

    publication_entries(state)
    |> Enum.flat_map(&publication_item_lines(&1, state, focus))
  end

  defp current_channel(state) do
    case current_focus(state) do
      %{channel: channel} -> channel
      _other -> Enum.at(state.publish_selected, 0)
    end
  end

  defp preview_lines(_state, nil, _width), do: ["No channel selected."]

  defp preview_lines(state, channel, width) do
    publication =
      publication_entries(state)
      |> Enum.find(fn publication -> publication["channel"] == channel end)

    if publication,
      do: Projection.publish_preview_lines(channel, publication, width),
      else: ["No preview available."]
  end

  defp binding_description(state, _channel, field) do
    publication_entries(state)
    |> Enum.flat_map(&(&1["required_bindings"] || []))
    |> Enum.find_value(field, fn binding ->
      if binding["field"] == field, do: binding["description"]
    end)
    |> to_string()
  end

  defp auth_summary(state) do
    state.publish_selected
    |> Enum.map(fn channel ->
      case Map.get(state.publish_auth_state, channel) do
        %{status: :cached, connection_id: connection_id, source: :server}
        when is_binary(connection_id) and connection_id != "" ->
          "#{channel}: connected (#{connection_id})"

        %{status: :cached, connection_id: connection_id}
        when is_binary(connection_id) and connection_id != "" ->
          "#{channel}: cached locally (#{connection_id})"

        %{status: :pending, state: auth_state} when is_binary(auth_state) and auth_state != "" ->
          "#{channel}: #{auth_state} — finish connector setup before publishing"

        _other ->
          "#{channel}: not configured — run hive auth login #{channel}"
      end
    end)
    |> blank_to("Select a binding field to edit, or toggle a channel to include it.")
  end

  defp publication_item_lines(publication, state, focus) do
    channel = publication_channel(publication)

    [
      publication_channel_line(channel, state)
      | publication_binding_lines(publication, channel, state, focus)
    ]
  end

  defp publication_channel_line(channel, state) do
    selected = if channel in state.publish_selected, do: "[x]", else: "[ ]"
    auth = publication_channel_auth(channel, state)
    "#{selected} #{channel}  #{auth}"
  end

  defp publication_channel_auth(channel, state) do
    case Map.get(state.publish_auth_state, channel) do
      %{status: :cached, source: :server} -> "auth:connected"
      %{status: :cached} -> "auth:cached"
      %{status: :pending, state: auth_state} when is_binary(auth_state) -> "auth:#{auth_state}"
      _other -> "auth:missing"
    end
  end

  defp publication_binding_lines(publication, channel, state, focus) do
    Enum.map(publication["required_bindings"] || [], fn binding ->
      publication_binding_line(binding, channel, state, focus)
    end)
  end

  defp publication_binding_line(binding, channel, state, focus) do
    field = binding["field"]
    value = get_in(state.publish_bindings, [channel, field]) || ""
    description = binding["description"] || field
    marker = publication_binding_marker(focus, channel, field)
    "#{marker} #{field}: #{Projection.truncate(value, 28)}  (#{description})"
  end

  defp publication_binding_marker(
         %{type: :binding, channel: channel, field: field},
         channel,
         field
       ),
       do: "•"

  defp publication_binding_marker(_focus, _channel, _field), do: "-"

  defp blank_to([], fallback), do: fallback
  defp blank_to([_ | _] = lines, _fallback), do: Enum.join(lines, "\n")
  defp blank_to("", fallback), do: fallback
  defp blank_to(value, _fallback), do: value

  defp validate_selected_publications(state) do
    case missing_required_binding(state) do
      {channel, _field, description} -> {:error, "#{channel}: missing #{description}"}
      nil -> validate_cached_auth(state)
    end
  end

  defp missing_required_binding(state) do
    state
    |> required_bindings()
    |> Enum.find(fn {channel, field, _description} ->
      value = get_in(state.publish_bindings, [channel, field])
      is_nil(value) or String.trim(to_string(value)) == ""
    end)
  end

  defp validate_cached_auth(state) do
    if Enum.any?(
         state.publish_selected,
         &(state.operator_module.auth_status(state.publish_auth_state, &1) != :cached)
       ) do
      {:error, "Authentication incomplete for at least one selected channel"}
    else
      :ok
    end
  end

  defp required_bindings(state) do
    publication_entries(state)
    |> Enum.filter(&(publication_channel(&1) in state.publish_selected))
    |> Enum.flat_map(fn publication ->
      channel = publication_channel(publication)

      Enum.map(publication["required_bindings"] || [], fn binding ->
        {channel, binding["field"], binding["description"]}
      end)
    end)
  end

  defp publication_channel(publication), do: publication["channel"] || publication[:channel]
end
