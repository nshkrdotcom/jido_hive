defmodule JidoHiveTermuiConsole.App do
  @moduledoc false

  use ExRatatui.App
  require Logger

  alias ExRatatui.{Event, Frame}
  alias JidoHiveTermuiConsole.{Identity, Model, Nav, Projection}
  alias JidoHiveTermuiConsole.Screens.{Conflict, Lobby, Publish, Room, Wizard}

  @impl true
  def mount(opts) do
    {state, effects} = init(opts)
    state = state |> ensure_input_refs() |> sync_input_widgets()

    Logger.info(
      "console mounted screen=#{state.active_screen} room_id=#{state.room_id || "none"} participant_id=#{state.participant_id} api_base_url=#{state.api_base_url}"
    )

    :ok = schedule_effects(effects)
    {:ok, state}
  end

  @impl true
  def render(state, %Frame{} = frame) do
    view(state, frame)
  end

  @impl true
  def handle_event(%Event.Resize{width: width, height: height}, state) do
    dispatch_update({:resize, width, height}, state)
  end

  def handle_event(%Event.Key{kind: "press"} = event, state) do
    case event_to_msg(event, state) do
      :ignore -> {:noreply, state}
      {:msg, msg} -> dispatch_update(msg, state)
    end
  end

  def handle_event(_event, state), do: {:noreply, state}

  @impl true
  def handle_info(:poll, state) do
    dispatch_update(:poll, state)
  end

  def handle_info(msg, state) do
    {next_state, effects} = handle_message(msg, state)
    next_state = sync_input_widgets(next_state)

    case apply_effects(next_state, effects) do
      {:stop, final_state} -> {:stop, final_state}
      {:continue, final_state} -> {:noreply, final_state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    shutdown_children(state)
    :ok
  end

  @spec init(keyword()) :: {Model.t(), [term()]}
  def init(opts) do
    route = Keyword.get(opts, :route, {:lobby, %{}})
    state = Model.new(opts) |> ensure_input_refs()

    next_state =
      case route do
        {:room, %{room_id: room_id}} ->
          Nav.transition(state, :room, room_id: room_id, app_pid: self())

        _other ->
          Nav.transition(state, :lobby, app_pid: self())
      end

    {next_state, [{:timer, 0, :poll}]}
  end

  @spec event_to_msg(Event.t(), Model.t()) :: :ignore | {:msg, term()}
  def event_to_msg(%Event.Resize{width: width, height: height}, _state) do
    {:msg, {:resize, width, height}}
  end

  def event_to_msg(%Event.Key{} = event, state) do
    case global_event_to_msg(event, state) do
      :ignore ->
        :ignore

      nil ->
        case screen_module(state).event_to_msg(event, state) do
          nil -> :ignore
          msg -> {:msg, msg}
        end

      msg ->
        {:msg, msg}
    end
  end

  def event_to_msg(_event, _state), do: :ignore

  @spec update(term(), Model.t()) :: {Model.t(), [term()]}
  def update(:quit, state), do: {state, [:quit]}
  def update(:show_help, state), do: {Model.show_help(state), []}
  def update(:dismiss_help, state), do: {Model.dismiss_help(state), []}
  def update(:show_debug, state), do: {Model.show_debug(state), []}
  def update(:dismiss_debug, state), do: {Model.dismiss_debug(state), []}

  def update(:toggle_help, state) do
    next_state =
      if(state.help_visible, do: Model.dismiss_help(state), else: Model.show_help(state))

    {next_state, []}
  end

  def update(:toggle_debug, state) do
    next_state =
      if(state.debug_visible, do: Model.dismiss_debug(state), else: Model.show_debug(state))

    {next_state, []}
  end

  def update({:resize, width, height}, state) do
    {Model.resize(state, width, height), []}
  end

  def update(:poll, state) do
    next_state =
      if state.active_screen in [:room, :conflict, :publish] do
        state
        |> Nav.refresh_room_snapshot()
        |> reconcile_pending_room_submit()
      else
        state
      end

    {next_state, [{:timer, state.poll_interval_ms, :poll}]}
  end

  def update(:lobby_prev, state), do: {Model.move_lobby_cursor(state, -1), []}
  def update(:lobby_next, state), do: {Model.move_lobby_cursor(state, 1), []}
  def update(:refresh_lobby, state), do: {Nav.transition(state, :lobby, app_pid: self()), []}

  def update(:remove_selected_room, state) do
    case Model.selected_lobby_room(state) do
      nil ->
        {Model.set_status(state, "No room selected", :error), []}

      %{room_id: room_id} ->
        case state.operator_module.remove_saved_room(room_id, state.api_base_url) do
          :ok ->
            {Nav.transition(state, :lobby, app_pid: self()), []}

          {:error, reason} ->
            {Model.set_status(state, "Remove failed: #{inspect(reason)}", :error), []}
        end
    end
  end

  def update(:open_selected_room, state) do
    case Model.selected_lobby_room(state) do
      nil ->
        {Model.set_status(state, "No room selected", :error), []}

      %{fetch_error: true} ->
        {Model.set_status(state, "Remove the stale room entry or refresh it first", :warn), []}

      %{room_id: room_id} ->
        {Nav.transition(state, :room, room_id: room_id, app_pid: self()), []}
    end
  end

  def update(:open_wizard, state) do
    {Nav.transition(state, :wizard, app_pid: self()), []}
  end

  def update(:select_prev, state) do
    if state.drill_context_id, do: {state, []}, else: {Model.move_selection(state, -1), []}
  end

  def update(:select_next, state) do
    if state.drill_context_id, do: {state, []}, else: {Model.move_selection(state, 1), []}
  end

  def update(
        {:room_input_key, _code},
        %{active_screen: :room, pending_room_submit: pending} = state
      )
      when not is_nil(pending) do
    {Model.set_status(state, "Chat submission is in progress", :warn), []}
  end

  def update({:room_input_key, code}, %{active_screen: :room} = state) do
    {handle_room_input_key(state, code), []}
  end

  def update(
        {:input_append, _char},
        %{active_screen: :room, pending_room_submit: pending} = state
      )
      when not is_nil(pending) do
    {Model.set_status(state, "Chat submission is in progress", :warn), []}
  end

  def update({:input_append, char}, %{active_screen: :room} = state) do
    {set_room_input(state, state.input_buffer <> char), []}
  end

  def update(:input_backspace, %{active_screen: :room, pending_room_submit: pending} = state)
      when not is_nil(pending) do
    {Model.set_status(state, "Chat submission is in progress", :warn), []}
  end

  def update(:input_backspace, %{active_screen: :room} = state) do
    {set_room_input(state, drop_last_grapheme(state.input_buffer)), []}
  end

  def update({:set_relation_mode, mode}, state) do
    next_state =
      state
      |> Model.set_relation_mode(mode)
      |> Model.set_status("Compose mode: #{Atom.to_string(mode)}", :info)

    {next_state, []}
  end

  def update(:cycle_pane_focus, state), do: {Model.cycle_pane_focus(state), []}

  def update(:refresh_room, state) do
    next_state =
      case state.embedded_module.refresh(state.embedded) do
        {:ok, _snapshot} ->
          state |> Nav.refresh_room_snapshot() |> Model.set_status("Refreshed", :info)

        {:error, reason} ->
          Model.set_status(state, "Refresh failed: #{inspect(reason)}", :error)
      end

    {next_state, []}
  end

  def update(:accept_selected, state) do
    case Model.selected_context(state) do
      nil ->
        {Model.set_status(state, "No context object selected", :error), []}

      context ->
        context_id = Map.get(context, "context_id") || Map.get(context, :context_id)

        case state.embedded_module.accept_context(state.embedded, context_id, %{}) do
          {:ok, _contribution} ->
            next_state =
              state
              |> Nav.refresh_room_snapshot()
              |> Model.set_status("Accepted selected context object", :info)

            {next_state, []}

          {:error, reason} ->
            {Model.set_status(state, "Accept failed: #{inspect(reason)}", :error), []}
        end
    end
  end

  def update(:toggle_drill, state) do
    next_state =
      case {state.drill_context_id, Model.selected_context(state)} do
        {_current, nil} ->
          Model.set_status(state, "No context object selected", :error)

        {nil, context} ->
          %{
            state
            | drill_context_id: Map.get(context, "context_id") || Map.get(context, :context_id),
              provenance_lines:
                Projection.provenance_tree(
                  context,
                  Map.get(state.snapshot, "context_objects") || []
                )
          }

        {_current, _context} ->
          %{state | drill_context_id: nil, provenance_lines: []}
      end

    {next_state, []}
  end

  def update(:room_escape, state) do
    if state.pending_room_submit do
      {Model.set_status(
         state,
         "Chat submission is in progress; wait or press Ctrl+C to quit",
         :warn
       ), []}
    else
      cond do
        state.drill_context_id ->
          {%{state | drill_context_id: nil, provenance_lines: []}, []}

        String.trim(state.input_buffer) != "" ->
          {set_room_input(state, ""), []}

        true ->
          {Nav.transition(state, :lobby, app_pid: self()), []}
      end
    end
  end

  def update(:back_to_lobby, %{pending_room_submit: pending} = state) when not is_nil(pending) do
    {Model.set_status(
       state,
       "Chat submission is in progress; wait or press Ctrl+C to quit",
       :warn
     ), []}
  end

  def update(:back_to_lobby, state) do
    {Nav.transition(state, :lobby, app_pid: self()), []}
  end

  def update(:room_enter, %{pending_room_submit: pending} = state) when not is_nil(pending) do
    {Model.set_status(state, "Chat submission already in progress", :warn), []}
  end

  def update(:room_enter, state) do
    case String.trim(state.input_buffer) do
      "" -> empty_room_enter(state)
      text -> queue_room_chat_submit(state, text)
    end
  end

  def update(:open_publish, state) do
    status = Map.get(state.snapshot, "status") || Map.get(state.snapshot, :status)

    if status == "publication_ready" do
      {Nav.transition(state, :publish, app_pid: self()), []}
    else
      {Model.set_status(state, "Room is not publication_ready", :warn), []}
    end
  end

  def update({:conflict_input_key, code}, state) do
    {handle_conflict_input_key(state, code), []}
  end

  def update({:conflict_append, char}, state) do
    {%{state | conflict_input_buf: state.conflict_input_buf <> char}, []}
  end

  def update(:conflict_backspace, state) do
    {%{state | conflict_input_buf: drop_last_grapheme(state.conflict_input_buf)}, []}
  end

  def update({:prefill_conflict, side}, state) do
    {%{state | conflict_input_buf: prefill_conflict_buffer(side, state)}, []}
  end

  def update(:dispatch_ai_synthesis, state) do
    base_attrs = %{
      text:
        "Synthesize a resolution for the contradiction between " <>
          "#{context_id(state.conflict_left)} (#{Map.get(state.conflict_left, "title")}) and " <>
          "#{context_id(state.conflict_right)} (#{Map.get(state.conflict_right, "title")}).",
      selected_context_id: context_id(state.conflict_left),
      selected_relation: "contextual"
    }

    submit_attrs = Identity.to_submit_attrs(identity(state), base_attrs)

    next_state =
      case state.embedded_module.submit_chat(state.embedded, submit_attrs) do
        {:ok, _contribution} ->
          state
          |> Nav.refresh_room_snapshot()
          |> Nav.transition(:room,
            room_id: state.room_id,
            preserve_existing: true,
            app_pid: self()
          )
          |> Model.set_status("Requested AI synthesis", :info)

        {:error, reason} ->
          Model.set_status(state, "AI synthesis failed: #{inspect(reason)}", :error)
      end

    {next_state, []}
  end

  def update(:cancel_conflict, state) do
    {Nav.transition(state, :room,
       room_id: state.room_id,
       preserve_existing: true,
       app_pid: self()
     ), []}
  end

  def update(:submit_conflict_resolution, state) do
    if String.trim(state.conflict_input_buf) == "" do
      {Model.set_status(state, "Type a resolution before submitting", :error), []}
    else
      payload =
        identity(state)
        |> Identity.to_contribution_base(state.room_id)
        |> Map.merge(%{
          "contribution_type" => "decision",
          "summary" => "Resolution: #{state.conflict_input_buf}",
          "context_objects" => [
            %{
              "object_type" => "decision",
              "title" => Projection.truncate(state.conflict_input_buf, 72),
              "body" => state.conflict_input_buf,
              "relations" => [
                %{"relation" => "resolves", "target_id" => context_id(state.conflict_left)},
                %{"relation" => "resolves", "target_id" => context_id(state.conflict_right)}
              ]
            }
          ]
        })

      next_state =
        case state.operator_module.submit_contribution(
               state.api_base_url,
               state.room_id,
               payload
             ) do
          {:ok, _response} ->
            state
            |> Nav.refresh_room_snapshot()
            |> Nav.transition(:room,
              room_id: state.room_id,
              preserve_existing: true,
              app_pid: self()
            )
            |> Model.set_status("Submitted conflict resolution", :info)

          {:error, reason} ->
            Model.set_status(state, "Resolution failed: #{inspect(reason)}", :error)
        end

      {next_state, []}
    end
  end

  def update(:publish_next_focus, state) do
    items = Publish.focus_items(state)
    next_cursor = if items == [], do: 0, else: rem(state.publish_cursor + 1, length(items))
    {%{state | publish_cursor: next_cursor}, []}
  end

  def update(:publish_toggle_current, state) do
    case Publish.current_focus(state) do
      nil ->
        {state, []}

      %{channel: channel} ->
        publish_selected =
          if channel in state.publish_selected do
            Enum.reject(state.publish_selected, &(&1 == channel))
          else
            state.publish_selected ++ [channel]
          end

        {%{state | publish_selected: publish_selected}, []}
    end
  end

  def update({:publish_input_key, code}, state) do
    {handle_publish_input_key(state, code), []}
  end

  def update({:publish_append, char}, state) do
    case Publish.current_focus(state) do
      %{type: :binding, channel: channel, field: field} ->
        value = get_in(state.publish_bindings, [channel, field]) || ""
        bindings = put_nested_binding(state.publish_bindings, channel, field, value <> char)
        {%{state | publish_bindings: bindings}, []}

      _other ->
        {state, []}
    end
  end

  def update(:publish_backspace, state) do
    case Publish.current_focus(state) do
      %{type: :binding, channel: channel, field: field} ->
        value = get_in(state.publish_bindings, [channel, field]) || ""

        bindings =
          put_nested_binding(state.publish_bindings, channel, field, drop_last_grapheme(value))

        {%{state | publish_bindings: bindings}, []}

      _other ->
        {state, []}
    end
  end

  def update(:publish_refresh_auth, state) do
    auth_state = state.operator_module.load_auth_state(state.api_base_url, state.participant_id)

    {%{state | publish_auth_state: auth_state}, []}
  end

  def update(:cancel_publish, state) do
    {Nav.transition(state, :room,
       room_id: state.room_id,
       preserve_existing: true,
       app_pid: self()
     ), []}
  end

  def update(:publish_submit, state) do
    case Publish.validate_submission(state) do
      :ok ->
        payload = %{
          "channels" => state.publish_selected,
          "bindings" => state.publish_bindings,
          "tenant_id" => state.tenant_id,
          "actor_id" => state.actor_id,
          "connections" =>
            Map.new(state.publish_selected, fn channel ->
              {channel, state.operator_module.connection_id(state.publish_auth_state, channel)}
            end)
        }

        next_state =
          case state.operator_module.publish_room(state.api_base_url, state.room_id, payload) do
            {:ok, _response} ->
              state
              |> Nav.refresh_room_snapshot()
              |> Model.set_status("Publication submitted", :info)

            {:error, reason} ->
              Model.set_status(state, "Publish failed: #{inspect(reason)}", :error)
          end

        {next_state, []}

      {:error, message} ->
        {Model.set_status(state, message, :error), []}
    end
  end

  def update(:wizard_prev_option, state), do: {Model.move_wizard_cursor(state, -1), []}
  def update(:wizard_next_option, state), do: {Model.move_wizard_cursor(state, 1), []}

  def update({:wizard_input_key, code}, %{wizard_step: 0} = state) do
    {handle_wizard_input_key(state, code), []}
  end

  def update({:wizard_append, char}, %{wizard_step: 0} = state) do
    fields = Map.update(state.wizard_fields, "brief", char, &(&1 <> char))
    {%{state | wizard_fields: fields}, []}
  end

  def update(:wizard_backspace, %{wizard_step: 0} = state) do
    brief = drop_last_grapheme(Map.get(state.wizard_fields, "brief", ""))
    {%{state | wizard_fields: Map.put(state.wizard_fields, "brief", brief)}, []}
  end

  def update(:wizard_toggle_worker, %{wizard_step: 3} = state) do
    worker = Enum.at(state.wizard_available_targets, state.wizard_cursor)
    current = Map.get(state.wizard_fields, "participants", [])

    next_workers =
      if worker && Enum.any?(current, &same_target?(&1, worker)) do
        Enum.reject(current, &same_target?(&1, worker))
      else
        current ++ if(worker, do: [worker], else: [])
      end

    {%{state | wizard_fields: Map.put(state.wizard_fields, "participants", next_workers)}, []}
  end

  def update(:wizard_escape, %{pending_room_create: pending} = state) when not is_nil(pending) do
    {Model.set_status(state, "Room creation is in progress; wait or press Ctrl+C to quit", :warn),
     []}
  end

  def update(:wizard_escape, state) do
    if state.wizard_step == 0 do
      {Nav.transition(state, :lobby, app_pid: self()), []}
    else
      {%{state | wizard_step: state.wizard_step - 1, wizard_cursor: 0}, []}
    end
  end

  def update(:wizard_enter, %{wizard_step: 4, pending_room_create: pending} = state)
      when not is_nil(pending) do
    {Model.set_status(state, "Room creation already in progress", :warn), []}
  end

  def update(:wizard_enter, state) do
    case state.wizard_step do
      0 -> wizard_submit_brief(state)
      1 -> wizard_submit_policy(state)
      2 -> {%{state | wizard_step: 3, wizard_cursor: 0}, []}
      3 -> wizard_submit_workers(state)
      4 -> wizard_create_room(state)
      _other -> {state, []}
    end
  end

  def update(_message, state), do: {state, []}

  @spec handle_message(term(), Model.t()) :: {Model.t(), [term()]}
  def handle_message({:fetch_room, room_id}, state) do
    next_state =
      case state.operator_module.fetch_room(state.api_base_url, room_id) do
        {:ok, snapshot} ->
          Lobby.upsert_row(state, Lobby.row_from_snapshot(room_id, snapshot))

        {:error, :not_found} ->
          Lobby.upsert_row(state, Lobby.fetch_error_row(room_id))

        {:error, _reason} ->
          Lobby.upsert_row(state, Lobby.fetch_error_row(room_id))
      end

    {next_state, []}
  end

  def handle_message(:fetch_wizard_targets, state) do
    next_state =
      case state.operator_module.list_targets(state.api_base_url) do
        {:ok, targets} ->
          state
          |> Map.put(:wizard_available_targets, targets)
          |> Map.put(:wizard_targets_state, :ready)
          |> maybe_set_empty_target_warning(targets)

        {:error, reason} ->
          state
          |> Map.put(:wizard_available_targets, [])
          |> Map.put(:wizard_targets_state, :error)
          |> Model.set_status("Target fetch failed: #{inspect(reason)}", :error)
      end

    {next_state, []}
  end

  def handle_message(:fetch_wizard_policies, state) do
    next_state =
      case state.operator_module.list_policies(state.api_base_url) do
        {:ok, policies} ->
          state
          |> Map.put(:wizard_available_policies, policies)
          |> Map.put(:wizard_policies_state, :ready)
          |> maybe_set_empty_policy_warning(policies)

        {:error, reason} ->
          state
          |> Map.put(:wizard_available_policies, [])
          |> Map.put(:wizard_policies_state, :error)
          |> Model.set_status("Policy fetch failed: #{inspect(reason)}", :error)
      end

    {next_state, []}
  end

  def handle_message(:fetch_publication_plan, state) do
    next_state =
      case state.operator_module.fetch_publication_plan(state.api_base_url, state.room_id) do
        {:ok, plan} ->
          %{state | publish_plan: plan}

        {:error, reason} ->
          Model.set_status(state, "Plan fetch failed: #{inspect(reason)}", :error)
      end

    {next_state, []}
  end

  def handle_message(:refresh_auth_state, state) do
    auth_state = state.operator_module.load_auth_state(state.api_base_url, state.participant_id)

    {%{state | publish_auth_state: auth_state}, []}
  end

  def handle_message({:room_submit_result, room_id, text, {:ok, _contribution}}, state) do
    next_state =
      case state.pending_room_submit do
        %{room_id: ^room_id, text: ^text} ->
          state
          |> Map.put(:pending_room_submit, nil)
          |> Nav.refresh_room_snapshot()
          |> Model.set_status("Submitted chat message", :info)

        _other ->
          state
      end

    {next_state, []}
  end

  def handle_message({:room_submit_result, room_id, text, {:error, reason}}, state) do
    next_state =
      case state.pending_room_submit do
        %{room_id: ^room_id, text: ^text} ->
          reconcile_room_submit_failure(state, room_id, text, reason)

        _other ->
          state
      end

    {next_state, []}
  end

  def handle_message({:wizard_create_result, room_id, {:ok, _response}}, state) do
    next_state =
      case state.pending_room_create do
        %{room_id: ^room_id} ->
          state
          |> Map.put(:pending_room_create, nil)
          |> Nav.transition(:room, room_id: room_id, app_pid: self())
          |> Model.set_status("Created room #{room_id}; run started in background", :info)

        _other ->
          state
      end

    if next_state.room_id == room_id do
      start_room_run_async(next_state, room_id)
    end

    {next_state, []}
  end

  def handle_message({:wizard_create_result, room_id, {:error, reason}}, state) do
    next_state =
      case state.pending_room_create do
        %{room_id: ^room_id} ->
          state
          |> Map.put(:pending_room_create, nil)
          |> Model.set_status("Room creation failed: #{inspect(reason)}", :error)

        _other ->
          state
      end

    {next_state, []}
  end

  def handle_message({:run_room_result, room_id, _operation_id, {:ok, _snapshot}}, state) do
    next_state =
      if state.room_id == room_id do
        state |> Nav.refresh_room_snapshot() |> Model.set_status("Room run completed", :info)
      else
        state
      end

    {next_state, []}
  end

  def handle_message(
        {:run_room_result, room_id, operation_id, {:error, {:timeout, metadata}}},
        state
      ) do
    next_state =
      if state.room_id == room_id do
        state
        |> Nav.refresh_room_snapshot()
        |> set_run_timeout_status(operation_id, metadata)
      else
        state
      end

    {next_state, []}
  end

  def handle_message({:run_room_result, room_id, _operation_id, {:error, reason}}, state) do
    next_state =
      if state.room_id == room_id do
        Model.set_status(state, "Room run failed: #{inspect(reason)}", :error)
      else
        state
      end

    {next_state, []}
  end

  def handle_message({:event_log_update, entries, cursor}, state) do
    formatted = entries |> Enum.map(&Projection.format_event_entry/1) |> Enum.reverse()
    lines = (formatted ++ state.event_log_lines) |> Enum.uniq() |> Enum.take(200)
    {%{state | event_log_lines: lines, event_log_cursor: cursor}, []}
  end

  def handle_message({:event_log_warning, reason}, state)
      when reason in [:not_found, :room_not_found] do
    {Model.set_status(
       state,
       "Event log polling stopped: room was not found on this server",
       :error
     ), []}
  end

  def handle_message({:event_log_warning, reason}, state) do
    {Model.set_status(state, "Event log warning: #{inspect(reason)}", :warn), []}
  end

  def handle_message({:EXIT, pid, reason}, state) do
    cond do
      pid == state.event_log_poller_pid and reason in [:normal, :shutdown] ->
        {%{state | event_log_poller_pid: nil}, []}

      pid == state.embedded and reason in [:normal, :shutdown] ->
        {%{state | embedded: nil}, []}

      true ->
        {state, []}
    end
  end

  def handle_message(_msg, state), do: {state, []}

  @spec view(Model.t()) :: [{term(), term()}]
  def view(state) do
    view(state, %Frame{width: state.screen_width, height: state.screen_height})
  end

  @spec view(Model.t(), Frame.t()) :: [{term(), term()}]
  def view(state, %Frame{} = frame) do
    sized_state = %{state | screen_width: frame.width, screen_height: frame.height}
    screen_module(sized_state).render(sized_state, frame)
  end

  defp wizard_submit_brief(state) do
    brief = String.trim(Map.get(state.wizard_fields, "brief", ""))

    if String.length(brief) < 10 do
      {Model.set_status(state, "Brief must be at least 10 characters", :error), []}
    else
      {%{state | wizard_step: 1, wizard_cursor: 0}, []}
    end
  end

  defp wizard_submit_policy(state) do
    cond do
      state.wizard_policies_state in [:idle, :loading] ->
        {Model.set_status(state, "Policies are still loading", :warn), []}

      state.wizard_policies_state == :error ->
        {Model.set_status(state, "Policies failed to load", :error), []}

      state.wizard_available_policies == [] ->
        {Model.set_status(state, "No policies available on this server", :warn), []}

      true ->
        policy = Enum.at(state.wizard_available_policies, state.wizard_cursor)
        phases = get_in(policy, ["config", "phases"]) || get_in(policy, [:config, :phases]) || []

        next_fields =
          state.wizard_fields
          |> Map.put("dispatch_policy_id", policy["policy_id"] || policy[:policy_id])
          |> Map.put("phases", phases)

        {%{state | wizard_fields: next_fields, wizard_step: 2, wizard_cursor: 0}, []}
    end
  end

  defp wizard_submit_workers(state) do
    workers = Map.get(state.wizard_fields, "participants", [])

    cond do
      workers != [] ->
        next_state =
          state
          |> Map.put(:wizard_step, 4)
          |> Map.put(:wizard_cursor, 0)
          |> Model.set_status("Press Enter to create and start the room", :info)

        {next_state, []}

      state.wizard_targets_state in [:idle, :loading] ->
        {Model.set_status(state, "Worker targets are still loading", :warn), []}

      state.wizard_targets_state == :error ->
        {Model.set_status(state, "Worker targets failed to load", :error), []}

      state.wizard_available_targets == [] ->
        {Model.set_status(state, "No worker targets available on this server", :warn), []}

      true ->
        {Model.set_status(state, "Select at least one worker", :error), []}
    end
  end

  defp wizard_create_room(state) do
    payload = Wizard.room_payload(state)
    room_id = payload["room_id"]

    next_state =
      state
      |> Map.put(:pending_room_create, %{room_id: room_id})
      |> Model.set_status("Creating room #{room_id}...", :info)

    {next_state, [{:wizard_create_room, room_id, payload}]}
  end

  defp screen_module(%{active_screen: :lobby}), do: Lobby
  defp screen_module(%{active_screen: :conflict}), do: Conflict
  defp screen_module(%{active_screen: :publish}), do: Publish
  defp screen_module(%{active_screen: :wizard}), do: Wizard
  defp screen_module(_state), do: Room

  defp global_event_to_msg(%Event.Key{code: code, modifiers: ["ctrl"]}, _state)
       when code in ["c", "q"],
       do: :quit

  defp global_event_to_msg(%Event.Key{code: code}, %{debug_visible: true})
       when code in ["enter", "esc", "f2"],
       do: :dismiss_debug

  defp global_event_to_msg(%Event.Key{}, %{debug_visible: true}), do: :ignore
  defp global_event_to_msg(%Event.Key{code: "f2"}, _state), do: :toggle_debug

  defp global_event_to_msg(%Event.Key{code: code, modifiers: ["ctrl"]}, %{help_visible: true})
       when code == "g", do: :dismiss_help

  defp global_event_to_msg(%Event.Key{code: "f2"}, %{help_visible: true}), do: :toggle_debug

  defp global_event_to_msg(%Event.Key{code: code}, %{help_visible: true})
       when code in ["enter", "esc", "f1"], do: :dismiss_help

  defp global_event_to_msg(%Event.Key{}, %{help_visible: true}), do: :ignore
  defp global_event_to_msg(%Event.Key{code: "g", modifiers: ["ctrl"]}, _state), do: :toggle_help
  defp global_event_to_msg(%Event.Key{code: "f1"}, _state), do: :toggle_help
  defp global_event_to_msg(_event, _state), do: nil

  defp identity(%Model{} = state) do
    %Identity{
      participant_id: state.participant_id,
      participant_role: state.participant_role,
      authority_level: state.authority_level,
      display_name: state.participant_id
    }
  end

  defp context_id(nil), do: nil
  defp context_id(object), do: Map.get(object, "context_id") || Map.get(object, :context_id)

  defp object_type(object), do: Map.get(object, "object_type") || Map.get(object, :object_type)

  defp empty_room_enter(state) do
    case Model.selected_context(state) do
      nil -> {Model.set_status(state, "Type a message or select a conflict", :warn), []}
      selected -> enter_selected_context(state, selected)
    end
  end

  defp enter_selected_context(state, selected) do
    if Projection.conflict?(selected, state.snapshot) do
      {Nav.transition(state, :conflict), []}
    else
      {Model.set_status(state, "Type a message before submitting", :warn), []}
    end
  end

  defp maybe_set_empty_target_warning(state, []),
    do: Model.set_status(state, "No worker targets available on this server", :warn)

  defp maybe_set_empty_target_warning(state, _targets), do: state

  defp maybe_set_empty_policy_warning(state, []),
    do: Model.set_status(state, "No policies available on this server", :warn)

  defp maybe_set_empty_policy_warning(state, _policies), do: state

  defp start_room_run_async(state, room_id) do
    caller = self()
    operator_module = state.operator_module
    api_base_url = state.api_base_url
    operation_id = JidoHiveClient.Operation.new_id("room_run")

    spawn(fn ->
      result =
        safe_async_result(fn ->
          operator_module.run_room(api_base_url, room_id,
            assignment_timeout_ms: 180_000,
            request_timeout_ms: 210_000,
            operation_id: operation_id
          )
        end)

      log_async_operation(operation_id, "room run", room_id, state.participant_id, result)

      send(caller, {:run_room_result, room_id, operation_id, result})
    end)

    :ok
  end

  defp start_room_create_async(state, room_id, payload) do
    caller = self()
    operator_module = state.operator_module
    api_base_url = state.api_base_url
    operation_id = JidoHiveClient.Operation.new_id("room_create")

    spawn(fn ->
      result =
        safe_async_result(fn ->
          create_room_and_store_config(operator_module, api_base_url, room_id, payload)
        end)

      log_async_operation(operation_id, "room create", room_id, state.participant_id, result)

      send(caller, {:wizard_create_result, room_id, result})
    end)

    :ok
  end

  defp start_room_submit_async(state, room_id, text, submit_attrs) do
    caller = self()
    embedded_module = state.embedded_module
    embedded = state.embedded
    operation_id = JidoHiveClient.Operation.new_id("room_submit")

    spawn(fn ->
      result =
        safe_async_result(fn ->
          embedded_module.submit_chat(embedded, submit_attrs)
        end)

      log_async_operation(operation_id, "room chat submit", room_id, state.participant_id, result)

      send(caller, {:room_submit_result, room_id, text, result})
    end)

    :ok
  end

  defp create_room_and_store_config(operator_module, api_base_url, room_id, payload) do
    with {:ok, response} <- operator_module.create_room(api_base_url, payload),
         :ok <- operator_module.add_saved_room(room_id, api_base_url) do
      {:ok, response}
    end
  end

  defp queue_room_chat_submit(state, text) do
    submit_attrs = Identity.to_submit_attrs(identity(state), room_submit_attrs(text, state))
    room_id = state.room_id

    Logger.info(
      "room chat submit started room_id=#{room_id} participant_id=#{state.participant_id} chars=#{String.length(text)}"
    )

    next_state =
      state
      |> Map.put(:pending_room_submit, %{room_id: room_id, text: text})
      |> Model.clear_input()
      |> Model.set_status("Submitting chat message...", :info)

    {next_state, [{:submit_room_chat, room_id, text, submit_attrs}]}
  end

  defp reconcile_pending_room_submit(%Model{pending_room_submit: nil} = state), do: state

  defp reconcile_pending_room_submit(%Model{} = state) do
    case state.pending_room_submit do
      %{text: text} ->
        if submit_visible_in_snapshot?(state.snapshot, state.participant_id, text) do
          state
          |> Map.put(:pending_room_submit, nil)
          |> Model.set_status("Submitted chat message", :info)
        else
          state
        end
    end
  end

  defp reconcile_room_submit_failure(%Model{} = state, _room_id, text, reason) do
    refreshed_state =
      state
      |> Map.put(:pending_room_submit, nil)
      |> Nav.refresh_room_snapshot()

    if submit_visible_in_snapshot?(refreshed_state.snapshot, state.participant_id, text) do
      Model.set_status(
        refreshed_state,
        "Chat message submitted; local acknowledgement failed, room refreshed",
        :warn
      )
    else
      refreshed_state
      |> set_room_input(text)
      |> Model.set_status("Submit failed: #{inspect(reason)}", :error)
    end
  end

  defp submit_visible_in_snapshot?(snapshot, participant_id, text) when is_binary(text) do
    normalized_text = String.trim(text)

    contribution_visible?(snapshot, participant_id, normalized_text) or
      context_message_visible?(snapshot, participant_id, normalized_text)
  end

  defp contribution_visible?(snapshot, participant_id, normalized_text) do
    snapshot
    |> Map.get("contributions", [])
    |> Enum.any?(fn contribution ->
      contribution_participant_id(contribution) == participant_id and
        String.trim(
          to_string(Map.get(contribution, "summary") || Map.get(contribution, :summary) || "")
        ) ==
          normalized_text
    end)
  end

  defp context_message_visible?(snapshot, participant_id, normalized_text) do
    snapshot
    |> Map.get("context_objects", [])
    |> Enum.any?(fn object ->
      object_type(object) == "message" and authored_by_participant_id(object) == participant_id and
        String.trim(to_string(Map.get(object, "body") || Map.get(object, :body) || "")) ==
          normalized_text
    end)
  end

  defp contribution_participant_id(contribution) do
    Map.get(contribution, "participant_id") ||
      Map.get(contribution, :participant_id) ||
      get_in(contribution, ["authored_by", "participant_id"]) ||
      get_in(contribution, [:authored_by, :participant_id])
  end

  defp authored_by_participant_id(object) do
    get_in(object, ["authored_by", "participant_id"]) ||
      get_in(object, [:authored_by, :participant_id])
  end

  defp safe_async_result(fun) when is_function(fun, 0) do
    fun.()
  rescue
    exception ->
      {:error, {:exception, Exception.message(exception)}}
  catch
    :exit, reason -> {:error, {:exit, reason}}
    kind, reason -> {:error, {kind, reason}}
  end

  defp log_async_operation(operation_id, label, room_id, participant_id, {:ok, _result}) do
    Logger.info(
      "#{label} completed operation_id=#{operation_id} room_id=#{room_id} participant_id=#{participant_id}"
    )
  end

  defp log_async_operation(operation_id, label, room_id, participant_id, {:error, reason}) do
    Logger.error(
      "#{label} failed operation_id=#{operation_id} room_id=#{room_id} participant_id=#{participant_id} reason=#{inspect(reason)}"
    )
  end

  defp set_run_timeout_status(state, operation_id, metadata) do
    timeout_ms = Map.get(metadata, :request_timeout_ms) || Map.get(metadata, "request_timeout_ms")

    if run_activity_visible?(state) do
      Model.set_status(
        state,
        "Room run response timed out locally after #{timeout_ms}ms, but server activity is visible. Continue watching Events. op=#{operation_id}",
        :warn
      )
    else
      Model.set_status(
        state,
        "Room run timed out locally after #{timeout_ms}ms with no visible progress. op=#{operation_id}",
        :error
      )
    end
  end

  defp run_activity_visible?(state) do
    snapshot = state.snapshot || %{}
    dispatch_state = Map.get(snapshot, "dispatch_state") || %{}

    Map.get(snapshot, "status") not in [nil, "idle"] or
      Map.get(dispatch_state, "completed_slots", 0) > 0 or
      Map.get(snapshot, "timeline", []) != [] or
      Map.get(snapshot, "context_objects", []) != [] or
      Enum.any?(state.event_log_lines)
  end

  defp room_submit_attrs(text, state) do
    case {Model.selected_context(state), state.relation_mode} do
      {_selected, :none} ->
        %{text: text}

      {nil, _mode} ->
        %{text: text}

      {selected, mode} ->
        %{
          text: text,
          selected_context_id: context_id(selected),
          selected_context_object_type: object_type(selected),
          selected_relation: Atom.to_string(mode)
        }
    end
  end

  defp prefill_conflict_buffer(:left, state) do
    "Accept: #{conflict_title(state.conflict_left, "left")}. Resolves conflict with #{conflict_id(state.conflict_right, "right")}."
  end

  defp prefill_conflict_buffer(:right, state) do
    "Accept: #{conflict_title(state.conflict_right, "right")}. Resolves conflict with #{conflict_id(state.conflict_left, "left")}."
  end

  defp conflict_title(object, fallback), do: Map.get(object || %{}, "title") || fallback
  defp conflict_id(object, fallback), do: Map.get(object || %{}, "context_id") || fallback

  defp same_target?(left, right) do
    (left["target_id"] || left[:target_id]) == (right["target_id"] || right[:target_id])
  end

  defp put_nested_binding(bindings, channel, field, value) do
    Map.update(bindings, channel, %{field => value}, &Map.put(&1, field, value))
  end

  defp dispatch_update(msg, state) do
    {next_state, effects} = update(msg, state)
    next_state = sync_input_widgets(next_state)

    case apply_effects(next_state, effects) do
      {:stop, final_state} -> {:stop, final_state}
      {:continue, final_state} -> {:noreply, final_state}
    end
  end

  defp apply_effects(state, effects) do
    Enum.reduce_while(effects, {:continue, state}, fn effect, {:continue, current_state} ->
      case effect do
        {:timer, timeout_ms, message} ->
          Process.send_after(self(), message, timeout_ms)
          {:cont, {:continue, current_state}}

        {:wizard_create_room, room_id, payload} ->
          start_room_create_async(current_state, room_id, payload)
          {:cont, {:continue, current_state}}

        {:submit_room_chat, room_id, text, submit_attrs} ->
          start_room_submit_async(current_state, room_id, text, submit_attrs)
          {:cont, {:continue, current_state}}

        :quit ->
          {:halt, {:stop, current_state}}

        _other ->
          {:cont, {:continue, current_state}}
      end
    end)
  end

  defp schedule_effects(effects) do
    Enum.each(effects, fn
      {:timer, timeout_ms, message} -> Process.send_after(self(), message, timeout_ms)
      _other -> :ok
    end)

    :ok
  end

  defp ensure_input_refs(%Model{} = state) do
    %{
      state
      | room_input_ref: state.room_input_ref || ExRatatui.text_input_new(),
        conflict_input_ref: state.conflict_input_ref || ExRatatui.text_input_new(),
        wizard_brief_input_ref: state.wizard_brief_input_ref || ExRatatui.text_input_new(),
        publish_input_ref: state.publish_input_ref || ExRatatui.text_input_new()
    }
  end

  defp sync_input_widgets(state) do
    state
    |> sync_room_input()
    |> sync_conflict_input()
    |> sync_wizard_input()
    |> sync_publish_input()
  end

  defp sync_room_input(%Model{room_input_ref: ref} = state) when is_reference(ref) do
    current = ExRatatui.text_input_get_value(ref)
    if current != state.input_buffer, do: ExRatatui.text_input_set_value(ref, state.input_buffer)
    state
  end

  defp sync_room_input(state), do: state

  defp sync_conflict_input(%Model{conflict_input_ref: ref} = state) when is_reference(ref) do
    current = ExRatatui.text_input_get_value(ref)

    if current != state.conflict_input_buf,
      do: ExRatatui.text_input_set_value(ref, state.conflict_input_buf)

    state
  end

  defp sync_conflict_input(state), do: state

  defp sync_wizard_input(%Model{wizard_brief_input_ref: ref} = state) when is_reference(ref) do
    desired = Map.get(state.wizard_fields, "brief", "")
    current = ExRatatui.text_input_get_value(ref)
    if current != desired, do: ExRatatui.text_input_set_value(ref, desired)
    state
  end

  defp sync_wizard_input(state), do: state

  defp sync_publish_input(%Model{publish_input_ref: ref} = state) when is_reference(ref) do
    desired =
      case Publish.current_focus(state) do
        %{type: :binding, channel: channel, field: field} ->
          get_in(state.publish_bindings, [channel, field]) || ""

        _other ->
          ""
      end

    current = ExRatatui.text_input_get_value(ref)
    if current != desired, do: ExRatatui.text_input_set_value(ref, desired)
    state
  end

  defp sync_publish_input(state), do: state

  defp handle_room_input_key(state, code) do
    case state.room_input_ref do
      ref when is_reference(ref) ->
        ExRatatui.text_input_handle_key(ref, code)
        %{state | input_buffer: ExRatatui.text_input_get_value(ref)}

      _other ->
        %{state | input_buffer: fallback_edit(state.input_buffer, code)}
    end
  end

  defp handle_conflict_input_key(state, code) do
    case state.conflict_input_ref do
      ref when is_reference(ref) ->
        ExRatatui.text_input_handle_key(ref, code)
        %{state | conflict_input_buf: ExRatatui.text_input_get_value(ref)}

      _other ->
        %{state | conflict_input_buf: fallback_edit(state.conflict_input_buf, code)}
    end
  end

  defp handle_wizard_input_key(state, code) do
    case state.wizard_brief_input_ref do
      ref when is_reference(ref) ->
        ExRatatui.text_input_handle_key(ref, code)

        %{
          state
          | wizard_fields:
              Map.put(state.wizard_fields, "brief", ExRatatui.text_input_get_value(ref))
        }

      _other ->
        brief = fallback_edit(Map.get(state.wizard_fields, "brief", ""), code)
        %{state | wizard_fields: Map.put(state.wizard_fields, "brief", brief)}
    end
  end

  defp handle_publish_input_key(state, code) do
    case Publish.current_focus(state) do
      %{type: :binding, channel: channel, field: field} ->
        value =
          case state.publish_input_ref do
            ref when is_reference(ref) ->
              ExRatatui.text_input_handle_key(ref, code)
              ExRatatui.text_input_get_value(ref)

            _other ->
              fallback_edit(get_in(state.publish_bindings, [channel, field]) || "", code)
          end

        %{
          state
          | publish_bindings: put_nested_binding(state.publish_bindings, channel, field, value)
        }

      _other ->
        state
    end
  end

  defp set_room_input(state, value), do: %{state | input_buffer: value}

  defp fallback_edit(value, "backspace"), do: drop_last_grapheme(value)

  defp fallback_edit(value, code) when code in ["delete", "left", "right", "home", "end"],
    do: value

  defp fallback_edit(value, code) when is_binary(code), do: value <> code

  defp drop_last_grapheme(value) do
    value |> String.graphemes() |> Enum.drop(-1) |> Enum.join()
  end

  defp shutdown_children(state) do
    stop_poller(state.event_log_poller_pid)
    stop_embedded(state.embedded_module, state.embedded)
  end

  defp stop_poller(pid) when is_pid(pid), do: Process.exit(pid, :shutdown)
  defp stop_poller(_pid), do: :ok

  defp stop_embedded(_module, nil), do: :ok

  defp stop_embedded(module, embedded) do
    if function_exported?(module, :shutdown, 1),
      do: module.shutdown(embedded),
      else: Process.exit(embedded, :shutdown)
  end
end
