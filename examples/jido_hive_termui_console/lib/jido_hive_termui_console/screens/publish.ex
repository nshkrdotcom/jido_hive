defmodule JidoHiveTermuiConsole.Screens.Publish do
  @moduledoc false

  import TermUI.Component.Helpers

  alias JidoHiveTermuiConsole.{Model, Projection}
  alias TermUI.Event
  alias TermUI.Renderer.Style

  @spec event_to_msg(Event.t(), Model.t()) :: term() | nil
  def event_to_msg(%Event.Key{key: :tab}, _state), do: :publish_next_focus
  def event_to_msg(%Event.Key{key: :enter}, _state), do: :publish_submit
  def event_to_msg(%Event.Key{key: :backspace}, _state), do: :publish_backspace
  def event_to_msg(%Event.Key{key: :escape}, _state), do: :cancel_publish

  def event_to_msg(%Event.Key{char: "q", modifiers: modifiers}, _state) when is_list(modifiers) do
    if Enum.member?(modifiers, :ctrl), do: :quit, else: nil
  end

  def event_to_msg(%Event.Key{char: " "}, _state), do: :publish_toggle_current
  def event_to_msg(%Event.Key{char: "r"}, _state), do: :publish_refresh_auth

  def event_to_msg(%Event.Key{char: char}, _state) when is_binary(char) and char != "",
    do: {:publish_append, char}

  def event_to_msg(_event, _state), do: nil

  @spec render(Model.t()) :: term()
  def render(%Model{} = state) do
    publications = publication_entries(state)
    width = max(state.screen_width - 2, 48)
    current_channel = current_channel(state)
    preview_lines = preview_lines(state, current_channel, width)

    stack(:vertical, [
      text("PUBLISH", header_style()),
      text("Room: #{state.room_id}", meta_style()),
      box(Enum.map(publication_lines(state, publications), &text/1), width: width, height: 16),
      box(
        [
          text("Preview (#{current_channel || "none"})", pane_title_style())
          | Enum.map(preview_lines, &text/1)
        ],
        width: width,
        height: 12
      ),
      text(
        "Space toggle channel  ·  Tab cycle input fields  ·  Enter publish  ·  r refresh auth  ·  ESC cancel",
        meta_style()
      ),
      text(state.status_line, status_style(state))
    ])
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

  defp publication_lines(state, publications) do
    if publications == [] do
      ["Loading publication plan..."]
    else
      focus = current_focus(state)
      Enum.flat_map(publications, &publication_block_lines(state, &1, focus))
    end
  end

  defp current_channel(state) do
    case current_focus(state) do
      %{channel: channel} -> channel
      _other -> List.first(state.publish_selected)
    end
  end

  defp preview_lines(_state, nil, _width), do: ["No channel selected."]

  defp preview_lines(state, channel, width) do
    publication =
      publication_entries(state)
      |> Enum.find(fn publication -> publication["channel"] == channel end)

    if publication do
      Projection.publish_preview_lines(channel, publication, width)
    else
      ["No preview available."]
    end
  end

  defp header_style, do: Style.new(fg: :cyan, attrs: [:bold])
  defp pane_title_style, do: Style.new(fg: :green, attrs: [:bold])
  defp meta_style, do: Style.new(fg: :bright_black)
  defp status_style(%{status_severity: :error}), do: Style.new(fg: :red, attrs: [:bold])
  defp status_style(%{status_severity: :warn}), do: Style.new(fg: :yellow)
  defp status_style(_state), do: Style.new(fg: :yellow)

  defp validate_selected_publications(state) do
    case missing_required_binding(state) do
      {channel, _field, description} ->
        {:error, "#{channel}: missing #{description}"}

      nil ->
        validate_cached_auth(state)
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
    if Enum.any?(state.publish_selected, &(state.auth_module.connection_id(&1) in [nil, ""])) do
      {:error, "Missing cached auth for at least one selected channel"}
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

  defp publication_block_lines(state, publication, focus) do
    channel = publication_channel(publication)
    selected = channel in state.publish_selected
    checkbox = if selected, do: "[x]", else: "[ ]"
    pointer = if focus && focus.channel == channel, do: ">", else: " "

    ["#{pointer} #{checkbox} #{channel}"] ++
      binding_lines(state, publication, channel) ++
      [auth_line(state, channel), ""]
  end

  defp binding_lines(state, publication, channel) do
    Enum.flat_map(publication["required_bindings"] || [], fn binding ->
      field = binding["field"]
      value = get_in(state.publish_bindings, [channel, field]) || ""
      ["  #{binding["description"]}", "  #{field}: [#{value}]"]
    end)
  end

  defp auth_line(state, channel) do
    auth_state = Map.get(state.publish_auth_state, channel, :missing)

    case {auth_state, state.auth_module.connection_id(channel)} do
      {:cached, connection_id} when is_binary(connection_id) ->
        "  auth:  ✓ cached (#{connection_id})"

      _other ->
        "  auth:  ✗ not configured — run: hive auth login #{channel}"
    end
  end

  defp publication_channel(publication) do
    publication["channel"] || publication[:channel]
  end
end
