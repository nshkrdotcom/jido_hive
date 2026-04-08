defmodule JidoHiveTermuiConsole.Screens.Lobby do
  @moduledoc false

  import TermUI.Component.Helpers

  alias JidoHiveTermuiConsole.{Model, Projection}
  alias TermUI.Event
  alias TermUI.Renderer.Style

  @spec event_to_msg(Event.t(), Model.t()) :: term() | nil
  def event_to_msg(%Event.Key{key: :up}, _state), do: :lobby_prev
  def event_to_msg(%Event.Key{key: :down}, _state), do: :lobby_next
  def event_to_msg(%Event.Key{key: :enter}, _state), do: :open_selected_room
  def event_to_msg(%Event.Key{char: char}, _state) when char in ["n", "N"], do: :open_wizard
  def event_to_msg(%Event.Key{char: char}, _state) when char in ["r", "R"], do: :refresh_lobby

  def event_to_msg(%Event.Key{char: char}, _state) when char in ["d", "D"],
    do: :remove_selected_room

  def event_to_msg(%Event.Key{char: char}, _state) when char in ["q", "Q"], do: :quit

  def event_to_msg(%Event.Key{char: "q", modifiers: modifiers}, _state) when is_list(modifiers) do
    if Enum.member?(modifiers, :ctrl), do: :quit, else: nil
  end

  def event_to_msg(_event, _state), do: nil

  @spec render(Model.t()) :: term()
  def render(%Model{} = state) do
    width = max(state.screen_width - 2, 60)
    lines = Projection.lobby_rows(state.lobby_rooms, state.lobby_cursor, width)

    stack(:vertical, [
      text("Jido Hive Console  ·  workspace-local  ·  #{identity_label(state)}", header_style()),
      text("Rooms: ~/.config/hive/rooms.json", meta_style()),
      box(Enum.map(lines, &text(&1)), width: width),
      text("Enter open  ·  n new room  ·  r refresh  ·  d remove  ·  q quit", meta_style()),
      text(state.status_line, status_style(state))
    ])
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
      brief: "[fetch error — press d to remove]",
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
        nil ->
          {state.lobby_rooms ++ [row], state.lobby_cursor}

        index ->
          {List.replace_at(state.lobby_rooms, index, row), state.lobby_cursor}
      end

    %{state | lobby_rooms: rooms, lobby_cursor: cursor, lobby_loading: false}
  end

  defp identity_label(state) do
    "#{state.participant_id} (#{state.participant_role} / #{String.upcase(state.authority_level)})"
  end

  defp header_style, do: Style.new(fg: :cyan, attrs: [:bold])
  defp meta_style, do: Style.new(fg: :bright_black)

  defp status_style(%{status_severity: :error}), do: Style.new(fg: :red, attrs: [:bold])
  defp status_style(%{status_severity: :warn}), do: Style.new(fg: :yellow)
  defp status_style(_state), do: Style.new(fg: :yellow)
end
