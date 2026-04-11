defmodule JidoHive.Switchyard.TUI.RoomsView do
  @moduledoc false

  alias JidoHive.Switchyard.TUI.State
  alias Switchyard.TUI.{Model, ScreenUI}

  @spec widgets(Model.t(), ExRatatui.Frame.t(), State.t()) :: list()
  def widgets(%Model{} = model, %ExRatatui.Frame{} = frame, %State{} = state) do
    area = ScreenUI.root_area(frame)

    [header_area, workflow_area, main_area, input_area, footer_area, status_area] =
      ExRatatui.Layout.split(area, :vertical, [
        {:length, 3},
        {:length, 8},
        {:min, 10},
        {:length, 5},
        {:length, 2},
        {:length, 1}
      ])

    [left_area, center_area, right_area] =
      ExRatatui.Layout.split(main_area, :horizontal, [
        {:percentage, 34},
        {:percentage, 28},
        {:percentage, 38}
      ])

    [conversation_area, events_area] =
      ExRatatui.Layout.split(left_area, :vertical, [{:min, 8}, {:length, 7}])

    panes = workspace_panes(state)

    widgets = [
      {ScreenUI.pane(header_title(state), header_lines(state), border_fg: :cyan), header_area},
      {ScreenUI.pane("Workflow", panes.workflow, border_fg: :cyan), workflow_area},
      {ScreenUI.pane("Conversation", panes.conversation, border_fg: :cyan), conversation_area},
      {ScreenUI.pane("Events", panes.events, border_fg: :green), events_area},
      {ScreenUI.pane(center_title(state), panes.graph, border_fg: :yellow), center_area},
      {ScreenUI.pane("Selected Detail", panes.detail, border_fg: :green), right_area},
      {ScreenUI.pane("Compose Steering Message", String.split(state.draft, "\n"),
         border_fg: :yellow
       ), input_area},
      {ScreenUI.text_widget(footer_text(state), style: ScreenUI.meta_style()), footer_area},
      {ScreenUI.text_widget(model.status_line,
         style: ScreenUI.status_style(model.status_severity),
         wrap: false
       ), status_area}
    ]

    case state.overlay do
      %{kind: :provenance, payload: provenance} ->
        widgets ++
          [ScreenUI.popup("Provenance", provenance_lines(provenance), frame, border_fg: :yellow)]

      %{kind: :publish} ->
        widgets ++
          [
            ScreenUI.popup(
              "Publish",
              publication_lines(state.publication_workspace || %{}, state),
              frame,
              border_fg: :yellow
            )
          ]

      _other ->
        widgets
    end
  end

  defp header_title(%State{screen: :rooms}), do: "Jido Hive Rooms"
  defp header_title(%State{room_id: room_id}), do: "Room #{room_id}"

  defp header_lines(%State{screen: :rooms} = state) do
    selected =
      case State.selected_room(state) do
        nil -> "No room selected"
        room -> room.brief || room.room_id
      end

    ["Select a room workspace to inspect.", "Selected: #{selected}"]
  end

  defp header_lines(%State{room_workspace: workspace}) when is_map(workspace) do
    ["Objective: #{Map.get(workspace, :objective) || ""}"]
  end

  defp header_lines(_state), do: [""]

  defp center_title(%State{screen: :rooms}), do: "Saved Rooms"
  defp center_title(_state), do: "Shared Graph"

  defp footer_text(%State{screen: :rooms}),
    do: "Up/Down select room  ·  Enter open  ·  Esc back  ·  Ctrl+Q quit"

  defp footer_text(%State{overlay: %{kind: :publish}}),
    do: "Type binding values  ·  Tab next field  ·  Enter publish  ·  Esc close  ·  Ctrl+Q quit"

  defp footer_text(_state),
    do:
      "Up/Down select context  ·  Enter send  ·  Ctrl+E provenance  ·  Ctrl+P publish  ·  Ctrl+R refresh  ·  Ctrl+C clear draft  ·  Esc back  ·  Ctrl+Q quit"

  defp workspace_panes(%State{screen: :rooms} = state) do
    %{
      workflow: ["Open a room to inspect workflow truth and the shared graph."],
      conversation: ["Room list mode."],
      events: ["No room events yet."],
      graph: rooms_lines(state.rooms, state.room_cursor),
      detail: rooms_detail_lines(State.selected_room(state))
    }
  end

  defp workspace_panes(%State{room_workspace: workspace}) when is_map(workspace) do
    %{
      workflow: workflow_lines(workspace),
      conversation: conversation_lines(workspace),
      events: event_lines(workspace),
      graph: graph_lines(workspace),
      detail: detail_lines(workspace.selected_detail)
    }
  end

  defp rooms_lines(rooms, cursor) do
    Enum.with_index(rooms, fn room, index ->
      prefix = if index == cursor, do: "> ", else: "  "
      "#{prefix}#{room.room_id}  ·  #{room.status}  ·  #{room.brief}"
    end)
  end

  defp rooms_detail_lines(nil), do: ["No room selected."]

  defp rooms_detail_lines(room) do
    [
      "Room ID: #{room.room_id}",
      "Status: #{room.status}",
      "Brief: #{room.brief}",
      "Slots: #{room.completed_slots}/#{room.total_slots}"
    ]
  end

  defp workflow_lines(workspace) do
    control_plane = Map.get(workspace, :control_plane, %{})

    focus_lines =
      control_plane
      |> Map.get(:focus_queue, [])
      |> Enum.map(fn item ->
        "- #{item.kind}: #{item.title || item.context_id}  ·  #{item.action}"
      end)

    [
      "Objective: #{control_plane.objective}",
      "Stage: #{control_plane.stage}",
      "Next: #{control_plane.next_action}",
      "Why: #{control_plane.reason}"
    ] ++ if(focus_lines == [], do: ["No active focus items."], else: focus_lines)
  end

  defp conversation_lines(workspace) do
    case Map.get(workspace, :conversation, []) do
      [] -> ["No conversation entries."]
      entries -> Enum.map(entries, &conversation_line/1)
    end
  end

  defp event_lines(workspace) do
    entries = Map.get(workspace, :events, [])

    if entries == [] do
      ["No room events yet."]
    else
      Enum.map(entries, fn entry ->
        "#{entry.kind}  #{entry.status || "completed"}  participant=#{entry.participant_id || "unknown"}"
      end)
    end
  end

  defp graph_lines(workspace) do
    workspace
    |> Map.get(:graph_sections, [])
    |> Enum.flat_map(&graph_section_lines/1)
  end

  defp detail_lines(nil), do: ["No context object selected."]

  defp detail_lines(detail) do
    actions =
      detail
      |> Map.get(:recommended_actions, [])
      |> Enum.map(fn action -> "  #{action.shortcut}: #{action.label}" end)

    [
      "Context ID: #{detail.context_id}",
      "Type: #{detail.object_type}",
      "Title: #{detail.title}",
      "Body: #{detail.body}",
      "Graph: in=#{detail.graph.incoming} out=#{detail.graph.outgoing}"
    ] ++ if(actions == [], do: [], else: ["", "Recommended Actions"] ++ actions)
  end

  defp provenance_lines(%{trace: trace, recommended_actions: actions}) do
    trace_lines =
      Enum.map(trace, fn entry ->
        indent = String.duplicate("  ", entry.depth)
        via = if(entry.via, do: " via #{entry.via}", else: "")
        "#{indent}- #{entry.title}#{via}"
      end)

    action_lines =
      Enum.map(actions, fn action ->
        "#{action.shortcut}: #{action.label}"
      end)

    trace_lines ++ if(action_lines == [], do: [], else: ["", "Recommended"] ++ action_lines)
  end

  defp provenance_lines(_other), do: ["No provenance available."]

  defp publication_lines(workspace, %State{} = state) do
    channel_lines =
      workspace
      |> Map.get(:channels, [])
      |> Enum.flat_map(fn channel ->
        binding_lines =
          Enum.map(channel.required_bindings, fn binding ->
            value = State.current_publish_value(state, channel.channel, binding.field)
            "- #{binding.field}: #{value}"
          end)

        ["#{channel.channel}: #{auth_label(channel.auth)}"] ++ binding_lines
      end)

    preview_lines = Map.get(workspace, :preview_lines, ["No preview available."])
    readiness_lines = Map.get(workspace, :readiness, ["No readiness information available."])

    channel_lines ++ ["", "Preview"] ++ preview_lines ++ ["", "Readiness"] ++ readiness_lines
  end

  defp item_flags(flags) do
    []
    |> maybe_add_flag(flags.binding, " [BINDING]")
    |> maybe_add_flag(flags.conflict, " [CONFLICT]")
    |> maybe_add_flag(flags.stale, " [STALE]")
    |> maybe_add_flag(flags.duplicate_count > 0, " [DUP:#{flags.duplicate_count}]")
    |> Enum.join()
  end

  defp auth_label(%{status: :cached, connection_id: connection_id}) when is_binary(connection_id),
    do: "connected (#{connection_id})"

  defp auth_label(%{status: :connected}), do: "connected"
  defp auth_label(%{status: :pending, state: state}) when is_binary(state), do: state
  defp auth_label(_auth), do: "not configured"

  defp conversation_line(entry) do
    prefix = if entry.pending?, do: "[pending] ", else: ""
    "#{prefix}#{entry.participant_id}: #{entry.body}"
  end

  defp graph_section_lines(section) do
    [section.title | Enum.map(section.items, &graph_item_line/1)]
  end

  defp graph_item_line(item) do
    graph_suffix = " [in:#{item.graph.incoming} out:#{item.graph.outgoing}]"
    selected = if item.selected?, do: "> ", else: "  "
    flags = item_flags(item.flags)
    "#{selected}#{item.title}#{graph_suffix}#{flags}"
  end

  defp maybe_add_flag(flags, true, value), do: [value | flags]
  defp maybe_add_flag(flags, false, _value), do: flags
end
