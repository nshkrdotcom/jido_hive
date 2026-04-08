defmodule JidoHiveTermuiConsole.Screens.Lobby do
  @moduledoc false

  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Paragraph, Table}
  alias JidoHiveTermuiConsole.{Model, Projection, ScreenUI}

  @spec event_to_msg(Event.t(), Model.t()) :: term() | nil
  def event_to_msg(%Event.Key{code: "up"}, _state), do: :lobby_prev
  def event_to_msg(%Event.Key{code: "down"}, _state), do: :lobby_next
  def event_to_msg(%Event.Key{code: "enter"}, _state), do: :open_selected_room
  def event_to_msg(%Event.Key{code: code}, _state) when code in ["n", "N"], do: :open_wizard
  def event_to_msg(%Event.Key{code: code}, _state) when code in ["r", "R"], do: :refresh_lobby

  def event_to_msg(%Event.Key{code: code}, _state) when code in ["d", "D"],
    do: :remove_selected_room

  def event_to_msg(%Event.Key{code: "q", modifiers: ["ctrl"]}, _state), do: :quit
  def event_to_msg(_event, _state), do: nil

  @spec render(Model.t(), %{width: pos_integer(), height: pos_integer()}) :: [{term(), term()}]
  def render(%Model{} = state, frame) do
    area = ScreenUI.root_area(frame)

    [header_area, subtitle_area, body_area, footer_top_area, footer_bottom_area, status_area] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:length, 1},
        {:min, 8},
        {:length, 1},
        {:length, 1},
        {:length, 1}
      ])

    widgets = [
      {header_widget(state), header_area},
      {subtitle_widget(), subtitle_area},
      {body_widget(state), body_area},
      {footer_widget("Ctrl+G guide  ·  ↑↓ select  ·  Enter open  ·  n new room"),
       footer_top_area},
      {footer_widget("r refresh  ·  d remove stale entry  ·  Ctrl+Q quit from lobby"),
       footer_bottom_area},
      {status_widget(state), status_area}
    ]

    widgets ++ ScreenUI.help_popup_widgets(frame, state, "Lobby Guide", help_lines())
  end

  @spec placeholder_row(String.t()) :: Model.lobby_row()
  def placeholder_row(room_id) do
    %{
      room_id: room_id,
      brief: "[loading]",
      status: "unknown",
      dispatch_policy_id: "",
      completed_slots: 0,
      total_slots: 0,
      participant_count: 0,
      flagged: false,
      fetch_error: false
    }
  end

  @spec fetch_error_row(String.t()) :: Model.lobby_row()
  def fetch_error_row(room_id) do
    %{
      room_id: room_id,
      brief: "[not found on this server — press d to remove]",
      status: "failed",
      dispatch_policy_id: "",
      completed_slots: 0,
      total_slots: 0,
      participant_count: 0,
      flagged: false,
      fetch_error: true
    }
  end

  @spec row_from_snapshot(String.t(), map()) :: Model.lobby_row()
  def row_from_snapshot(room_id, snapshot) do
    snapshot = Map.get(snapshot, "data", snapshot)
    dispatch_state = Map.get(snapshot, "dispatch_state", %{})

    %{
      room_id: room_id,
      brief: Map.get(snapshot, "brief", ""),
      status: Map.get(snapshot, "status", "unknown"),
      dispatch_policy_id: Map.get(snapshot, "dispatch_policy_id", ""),
      completed_slots: Map.get(dispatch_state, "completed_slots", 0),
      total_slots: Map.get(dispatch_state, "total_slots", 0),
      participant_count: length(Map.get(snapshot, "participants", [])),
      flagged: Map.get(snapshot, "status") == "needs_resolution",
      fetch_error: false
    }
  end

  @spec upsert_row(Model.t(), Model.lobby_row()) :: Model.t()
  def upsert_row(%Model{} = state, row) do
    {rooms, cursor} =
      case Enum.find_index(state.lobby_rooms, &(&1.room_id == row.room_id)) do
        nil -> {state.lobby_rooms ++ [row], state.lobby_cursor}
        index -> {List.replace_at(state.lobby_rooms, index, row), state.lobby_cursor}
      end

    %{state | lobby_rooms: rooms, lobby_cursor: cursor, lobby_loading: false}
  end

  defp header_widget(state) do
    %Paragraph{
      text: "Jido Hive Console  ·  #{server_label(state)}  ·  #{identity_label(state)}",
      style: ScreenUI.header_style(),
      block: ScreenUI.text_widget("", block: nil).block
    }
    |> Map.put(:block, panel_header_block())
  end

  defp subtitle_widget do
    ScreenUI.text_widget(
      "Rooms: ~/.config/hive/rooms.json (scoped to current server)",
      style: ScreenUI.meta_style(),
      wrap: false
    )
  end

  defp body_widget(%Model{lobby_rooms: []}) do
    ScreenUI.pane(
      "Saved Rooms",
      [
        "No saved rooms yet.",
        "",
        "Press n to open the new-room wizard.",
        "If you already know a room id, run: hive console --room-id <id>."
      ],
      border_fg: :cyan
    )
  end

  defp body_widget(%Model{} = state) do
    rows =
      Enum.map(state.lobby_rooms, fn row ->
        [
          Projection.truncate(row.room_id, 24),
          Projection.truncate(display_brief(row), 34),
          Projection.truncate(row.dispatch_policy_id || "", 18),
          "#{row.completed_slots}/#{row.total_slots}",
          row_flag(row)
        ]
      end)

    %Table{
      rows: rows,
      header: ["ROOM ID", "BRIEF", "POLICY", "SLOTS", "FLAG"],
      widths: [{:length, 24}, {:min, 20}, {:length, 18}, {:length, 7}, {:length, 5}],
      selected: if(rows == [], do: nil, else: state.lobby_cursor),
      highlight_symbol: "> ",
      column_spacing: 1,
      style: %Style{fg: :white},
      highlight_style: %Style{fg: :yellow, modifiers: [:bold]},
      block: panel_body_block()
    }
  end

  defp footer_widget(text) do
    ScreenUI.text_widget(text, style: ScreenUI.meta_style(), wrap: false)
  end

  defp status_widget(state) do
    ScreenUI.text_widget(state.status_line, style: ScreenUI.status_style(state), wrap: false)
  end

  defp identity_label(state) do
    "#{state.participant_id} (#{state.participant_role} / #{String.upcase(state.authority_level)})"
  end

  defp server_label(state) do
    uri = URI.parse(state.api_base_url || "")

    case uri.host do
      "127.0.0.1" -> "local"
      "localhost" -> "local"
      host when is_binary(host) and host != "" -> host
      _other -> state.api_base_url || "unknown server"
    end
  end

  defp display_brief(%{fetch_error: true}), do: "[fetch error — press d to remove]"
  defp display_brief(row), do: row.brief || ""

  defp row_flag(%{fetch_error: true}), do: "✗"

  defp row_flag(row) do
    cond do
      row.status == "publication_ready" -> "PUB"
      row.status == "needs_resolution" or row.flagged -> "⚡"
      row.status == "failed" -> "✗"
      true -> ""
    end
  end

  defp panel_header_block do
    %ExRatatui.Widgets.Block{
      borders: [:all],
      border_type: :rounded,
      border_style: %Style{fg: :cyan},
      padding: {1, 1, 0, 0}
    }
  end

  defp panel_body_block do
    %ExRatatui.Widgets.Block{
      title: "Saved Rooms",
      borders: [:all],
      border_type: :rounded,
      border_style: %Style{fg: :cyan},
      padding: {0, 0, 0, 0}
    }
  end

  defp help_lines do
    [
      "This is the home screen for the console.",
      "Use Up and Down to move through the saved room list.",
      "Press Enter to open the selected room.",
      "Press n to open the new-room wizard.",
      "Press r to refresh room summaries from the current server.",
      "Press d to remove a stale local room entry.",
      "Press Ctrl+Q to quit from the lobby."
    ]
  end
end
