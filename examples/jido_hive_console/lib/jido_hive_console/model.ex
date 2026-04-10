# credo:disable-for-this-file Credo.Check.Warning.StructFieldAmount
defmodule JidoHiveConsole.Model do
  @moduledoc false

  alias JidoHiveClient.RoomFlow
  alias JidoHiveConsole.Projection

  @default_snapshot %{
    "timeline" => [],
    "context_objects" => [],
    "last_error" => nil
  }

  defstruct [
    :embedded,
    :embedded_module,
    :event_log_poller_pid,
    :operator_module,
    :event_log_poller_module,
    :api_base_url,
    :tenant_id,
    :actor_id,
    :participant_id,
    :participant_role,
    :authority_level,
    :room_id,
    :room_flow,
    :snapshot,
    :room_input_ref,
    :conflict_input_ref,
    :wizard_brief_input_ref,
    :publish_input_ref,
    active_screen: :lobby,
    lobby_rooms: [],
    lobby_cursor: 0,
    lobby_loading: false,
    relation_mode: :contextual,
    input_buffer: "",
    selected_context_index: 0,
    pane_focus: :context,
    drill_context_id: nil,
    provenance_lines: [],
    event_log_lines: [],
    event_log_cursor: nil,
    conflict_left: nil,
    conflict_right: nil,
    conflict_input_buf: "",
    publish_plan: nil,
    publish_selected: [],
    publish_cursor: 0,
    publish_bindings: %{},
    publish_auth_state: %{},
    wizard_step: 0,
    wizard_fields: %{},
    wizard_cursor: 0,
    pending_room_submit: nil,
    pending_room_run: nil,
    wizard_available_targets: [],
    wizard_targets_state: :idle,
    wizard_available_policies: [],
    wizard_policies_state: :idle,
    pending_room_create: nil,
    status_animation_tick: 0,
    runtime_snapshot: nil,
    status_line: "Ready",
    status_severity: :info,
    sync_error: false,
    screen_width: 120,
    screen_height: 40,
    poll_interval_ms: 1_000,
    debug_visible: false,
    help_visible: false,
    help_scroll: 0,
    help_seen: MapSet.new()
  ]

  @type t :: %__MODULE__{}

  @type lobby_row :: %{
          room_id: String.t(),
          brief: String.t(),
          status: String.t(),
          dispatch_policy_id: String.t(),
          completed_slots: non_neg_integer(),
          total_slots: non_neg_integer(),
          participant_count: non_neg_integer(),
          flagged: boolean(),
          fetch_error: boolean()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    snapshot =
      opts
      |> Keyword.get(:snapshot, @default_snapshot)
      |> normalize_snapshot()

    room_id = Keyword.get(opts, :room_id) || value(snapshot, "room_id")
    room_flow = Keyword.get(opts, :room_flow) || maybe_room_flow(room_id)

    %__MODULE__{
      embedded: Keyword.get(opts, :embedded),
      embedded_module: Keyword.get(opts, :embedded_module, JidoHiveClient.RoomSession),
      event_log_poller_pid: Keyword.get(opts, :event_log_poller_pid),
      operator_module: Keyword.get(opts, :operator_module, JidoHiveClient.Operator),
      event_log_poller_module:
        Keyword.get(opts, :event_log_poller_module, JidoHiveConsole.EventLogPoller),
      api_base_url: Keyword.get(opts, :api_base_url, "http://127.0.0.1:4000/api"),
      tenant_id: Keyword.get(opts, :tenant_id, "workspace-local"),
      actor_id: Keyword.get(opts, :actor_id, "operator-1"),
      participant_id: Keyword.get(opts, :participant_id, "human-local"),
      participant_role: Keyword.get(opts, :participant_role, "coordinator"),
      authority_level: Keyword.get(opts, :authority_level, "binding"),
      active_screen: Keyword.get(opts, :active_screen, :lobby),
      room_id: room_id,
      room_flow: room_flow,
      snapshot: snapshot,
      relation_mode: Keyword.get(opts, :relation_mode, :contextual),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, 1_000),
      room_input_ref: Keyword.get(opts, :room_input_ref),
      conflict_input_ref: Keyword.get(opts, :conflict_input_ref),
      wizard_brief_input_ref: Keyword.get(opts, :wizard_brief_input_ref),
      publish_input_ref: Keyword.get(opts, :publish_input_ref)
    }
    |> apply_snapshot(snapshot)
  end

  @spec apply_snapshot(t(), map()) :: t()
  def apply_snapshot(%__MODULE__{} = state, snapshot) when is_map(snapshot) do
    normalized = normalize_snapshot(snapshot)
    room_id = state.room_id || value(normalized, "room_id")
    room_flow = ensure_room_flow(%{state | room_id: room_id})

    room_flow =
      if is_nil(room_flow), do: nil, else: RoomFlow.ingest_snapshot(room_flow, normalized)

    selected_index =
      normalized
      |> Projection.display_context_objects()
      |> clamp_index(state.selected_context_index)

    %{
      state
      | snapshot: normalized,
        room_id: room_id,
        room_flow: room_flow,
        selected_context_index: selected_index,
        sync_error: not is_nil(value(normalized, "last_error"))
    }
    |> apply_room_flow()
  end

  @spec append_input(t(), String.t()) :: t()
  def append_input(%__MODULE__{} = state, chunk) when is_binary(chunk) do
    %{state | input_buffer: state.input_buffer <> chunk}
  end

  @spec backspace(t()) :: t()
  def backspace(%__MODULE__{} = state) do
    %{state | input_buffer: drop_last_grapheme(state.input_buffer)}
  end

  @spec clear_input(t()) :: t()
  def clear_input(%__MODULE__{} = state), do: %{state | input_buffer: ""}

  @spec move_selection(t(), integer()) :: t()
  def move_selection(%__MODULE__{} = state, delta) when is_integer(delta) do
    max_index = max(length(Projection.display_context_objects(state.snapshot)) - 1, 0)
    next_index = min(max(state.selected_context_index + delta, 0), max_index)
    %{state | selected_context_index: next_index}
  end

  @spec move_lobby_cursor(t(), integer()) :: t()
  def move_lobby_cursor(%__MODULE__{} = state, delta) when is_integer(delta) do
    max_index = max(length(state.lobby_rooms) - 1, 0)
    next_index = min(max(state.lobby_cursor + delta, 0), max_index)
    %{state | lobby_cursor: next_index}
  end

  @spec move_wizard_cursor(t(), integer()) :: t()
  def move_wizard_cursor(%__MODULE__{} = state, delta) when is_integer(delta) do
    size =
      case state.wizard_step do
        1 -> length(state.wizard_available_policies)
        3 -> length(state.wizard_available_targets)
        _other -> 1
      end

    max_index = max(size - 1, 0)
    next_index = min(max(state.wizard_cursor + delta, 0), max_index)
    %{state | wizard_cursor: next_index}
  end

  @spec cycle_pane_focus(t()) :: t()
  def cycle_pane_focus(%__MODULE__{} = state) do
    next_focus =
      case state.pane_focus do
        :context -> :conversation
        :conversation -> :input
        _other -> :context
      end

    %{state | pane_focus: next_focus}
  end

  @spec show_help(t()) :: t()
  def show_help(%__MODULE__{} = state), do: %{state | help_visible: true, help_scroll: 0}

  @spec dismiss_help(t()) :: t()
  def dismiss_help(%__MODULE__{} = state) do
    %{
      state
      | help_visible: false,
        help_scroll: 0,
        help_seen: MapSet.put(state.help_seen, state.active_screen)
    }
  end

  @spec scroll_help(t(), integer()) :: t()
  def scroll_help(%__MODULE__{} = state, delta) when is_integer(delta) do
    %{state | help_scroll: max(state.help_scroll + delta, 0)}
  end

  @spec scroll_help(t(), integer(), non_neg_integer()) :: t()
  def scroll_help(%__MODULE__{} = state, delta, max_offset)
      when is_integer(delta) and is_integer(max_offset) do
    set_help_scroll(state, state.help_scroll + delta, max_offset)
  end

  @spec set_help_scroll(t(), integer()) :: t()
  def set_help_scroll(%__MODULE__{} = state, offset) when is_integer(offset) do
    %{state | help_scroll: max(offset, 0)}
  end

  @spec set_help_scroll(t(), integer(), non_neg_integer()) :: t()
  def set_help_scroll(%__MODULE__{} = state, offset, max_offset)
      when is_integer(offset) and is_integer(max_offset) do
    %{state | help_scroll: clamp_help_scroll(offset, max_offset)}
  end

  @spec show_debug(t()) :: t()
  def show_debug(%__MODULE__{} = state), do: %{state | debug_visible: true}

  @spec dismiss_debug(t()) :: t()
  def dismiss_debug(%__MODULE__{} = state), do: %{state | debug_visible: false}

  @spec selected_context(t()) :: map() | nil
  def selected_context(%__MODULE__{} = state) do
    state.snapshot
    |> Projection.display_context_objects()
    |> Enum.at(state.selected_context_index)
  end

  @spec selected_lobby_room(t()) :: lobby_row() | nil
  def selected_lobby_room(%__MODULE__{} = state),
    do: Enum.at(state.lobby_rooms, state.lobby_cursor)

  @spec resize(t(), pos_integer(), pos_integer()) :: t()
  def resize(%__MODULE__{} = state, width, height)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    %{state | screen_width: width, screen_height: height}
  end

  @spec set_status(t(), String.t(), :info | :warn | :error) :: t()
  def set_status(%__MODULE__{} = state, message, severity \\ :info)
      when is_binary(message) and severity in [:info, :warn, :error] do
    %{state | status_line: message, status_severity: severity}
  end

  @spec track_room_submit(t(), map()) :: t()
  def track_room_submit(%__MODULE__{} = state, operation) when is_map(operation) do
    case ensure_room_flow(state) do
      nil ->
        state

      room_flow ->
        %{state | room_flow: RoomFlow.submit_accepted(room_flow, operation)}
        |> apply_room_flow()
    end
  end

  @spec fail_room_submit(t(), String.t()) :: t()
  def fail_room_submit(%__MODULE__{} = state, reason) when is_binary(reason) do
    next_state = %{state | pending_room_submit: nil, status_animation_tick: 0}
    set_status(next_state, "Submit failed: #{reason}", :error)
  end

  @spec track_room_run(t(), map()) :: t()
  def track_room_run(%__MODULE__{} = state, operation) when is_map(operation) do
    case ensure_room_flow(state) do
      nil ->
        state

      room_flow ->
        %{state | room_flow: RoomFlow.run_accepted(room_flow, operation)}
        |> apply_room_flow()
    end
  end

  @spec set_relation_mode(t(), atom()) :: t()
  def set_relation_mode(%__MODULE__{} = state, mode)
      when mode in [
             :contextual,
             :references,
             :derives_from,
             :supports,
             :contradicts,
             :none,
             :resolves
           ] do
    %{state | relation_mode: mode}
  end

  defp clamp_index([], _selected_index), do: 0

  defp clamp_index(context_objects, selected_index) do
    max_index = max(length(context_objects) - 1, 0)
    min(max(selected_index, 0), max_index)
  end

  defp ensure_room_flow(%__MODULE__{} = state) do
    (state.room_flow || maybe_room_flow(state.room_id))
    |> maybe_seed_submit(state.pending_room_submit)
    |> maybe_seed_run(state.pending_room_run)
  end

  defp maybe_room_flow(room_id) when is_binary(room_id), do: RoomFlow.new(room_id)
  defp maybe_room_flow(_room_id), do: nil

  defp clamp_help_scroll(offset, max_offset) do
    offset
    |> max(0)
    |> min(max(max_offset, 0))
  end

  defp maybe_seed_submit(nil, _pending_room_submit), do: nil

  defp maybe_seed_submit(%RoomFlow{latest_submit: nil} = room_flow, %{
         operation_id: operation_id,
         text: text
       }) do
    RoomFlow.submit_accepted(room_flow, %{
      "operation_id" => operation_id,
      "status" => "accepted",
      "text" => text
    })
  end

  defp maybe_seed_submit(room_flow, _pending_room_submit), do: room_flow

  defp maybe_seed_run(nil, _pending_room_run), do: nil

  defp maybe_seed_run(
         %RoomFlow{latest_run: nil} = room_flow,
         %{
           operation_id: operation_id
         } = pending_room_run
       ) do
    RoomFlow.run_accepted(room_flow, %{
      "operation_id" => operation_id,
      "client_operation_id" => Map.get(pending_room_run, :client_operation_id),
      "status" => "accepted",
      "kind" => "room_run"
    })
  end

  defp maybe_seed_run(room_flow, _pending_room_run), do: room_flow

  defp apply_room_flow(%__MODULE__{room_flow: nil} = state), do: state

  defp apply_room_flow(%__MODULE__{} = state) do
    pending_room_submit =
      case RoomFlow.pending_submit(state.room_flow) do
        %{} = operation ->
          %{
            room_id: state.room_id,
            text: value(operation, "text"),
            operation_id: value(operation, "operation_id")
          }

        _other ->
          nil
      end

    pending_room_run =
      case RoomFlow.pending_run(state.room_flow) do
        %{} = operation ->
          %{
            room_id: state.room_id,
            operation_id: value(operation, "operation_id"),
            client_operation_id: value(operation, "client_operation_id")
          }

        _other ->
          nil
      end

    {status_severity, status_line} = RoomFlow.status(state.room_flow)

    %{
      state
      | pending_room_submit: pending_room_submit,
        pending_room_run: pending_room_run,
        status_line: status_line,
        status_severity: status_severity
    }
  end

  defp normalize_snapshot(snapshot) do
    @default_snapshot
    |> Map.merge(stringify_keys(snapshot))
    |> Map.put("timeline", value(snapshot, "timeline") || [])
    |> Map.put("context_objects", value(snapshot, "context_objects") || [])
    |> Map.put("contributions", value(snapshot, "contributions") || [])
    |> Map.put("operations", value(snapshot, "operations") || [])
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp drop_last_grapheme(buffer) do
    buffer
    |> String.graphemes()
    |> Enum.drop(-1)
    |> Enum.join()
  end
end
