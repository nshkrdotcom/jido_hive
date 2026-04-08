defmodule JidoHiveTermuiConsole.App do
  @moduledoc false

  use TermUI.Elm

  alias JidoHiveTermuiConsole.{
    Identity,
    Model,
    Nav,
    Projection
  }

  alias JidoHiveTermuiConsole.Screens.{Conflict, Lobby, Publish, Room, Wizard}
  alias TermUI.{Command, Event}

  @impl true
  def init(opts) do
    route = Keyword.get(opts, :route, {:lobby, %{}})
    state = Model.new(opts)

    next_state =
      case route do
        {:room, %{room_id: room_id}} ->
          Nav.transition(state, :room, room_id: room_id, app_pid: self())

        _other ->
          Nav.transition(state, :lobby, app_pid: self())
      end

    {next_state, [Command.timer(0, :poll)]}
  end

  @impl true
  def event_to_msg(%Event.Resize{width: width, height: height}, _state) do
    {:msg, {:resize, width, height}}
  end

  def event_to_msg(%Event.Key{} = event, state) do
    case screen_module(state).event_to_msg(event, state) do
      nil -> :ignore
      msg -> {:msg, msg}
    end
  end

  def event_to_msg(_event, _state), do: :ignore

  @impl true
  def update(:quit, state), do: {state, [Command.quit()]}

  def update({:resize, width, height}, state) do
    {Model.resize(state, width, height), []}
  end

  def update(:poll, state) do
    next_state =
      if state.active_screen in [:room, :conflict, :publish] do
        Nav.refresh_room_snapshot(state)
      else
        state
      end

    {next_state, [Command.timer(state.poll_interval_ms, :poll)]}
  end

  def update(:lobby_prev, state), do: {Model.move_lobby_cursor(state, -1), []}
  def update(:lobby_next, state), do: {Model.move_lobby_cursor(state, 1), []}
  def update(:refresh_lobby, state), do: {Nav.transition(state, :lobby, app_pid: self()), []}

  def update(:remove_selected_room, state) do
    case Model.selected_lobby_room(state) do
      nil ->
        {Model.set_status(state, "No room selected", :error), []}

      %{room_id: room_id} ->
        case config_remove_room(state.config_module, room_id, state.api_base_url) do
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
    if state.drill_context_id do
      {state, []}
    else
      {Model.move_selection(state, -1), []}
    end
  end

  def update(:select_next, state) do
    if state.drill_context_id do
      {state, []}
    else
      {Model.move_selection(state, 1), []}
    end
  end

  def update({:input_append, char}, %{active_screen: :room} = state) do
    {Model.append_input(state, char), []}
  end

  def update(:input_backspace, %{active_screen: :room} = state) do
    {Model.backspace(state), []}
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
          state
          |> Nav.refresh_room_snapshot()
          |> Model.set_status("Refreshed", :info)

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
    cond do
      state.drill_context_id ->
        {%{state | drill_context_id: nil, provenance_lines: []}, []}

      String.trim(state.input_buffer) != "" ->
        {Model.clear_input(state), []}

      true ->
        {Nav.transition(state, :lobby, app_pid: self()), []}
    end
  end

  def update(:back_to_lobby, state) do
    {Nav.transition(state, :lobby, app_pid: self()), []}
  end

  def update(:room_enter, state) do
    case String.trim(state.input_buffer) do
      "" -> empty_room_enter(state)
      text -> submit_room_chat(state, text)
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
    base_attrs =
      %{
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
        case state.http_module.post(
               state.api_base_url,
               "/rooms/#{URI.encode_www_form(state.room_id)}/contributions",
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

    next_cursor =
      if items == [] do
        0
      else
        rem(state.publish_cursor + 1, length(items))
      end

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
    {%{state | publish_auth_state: state.auth_module.load_all()}, []}
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
          "connections" =>
            Map.new(state.publish_selected, fn channel ->
              {channel, state.auth_module.connection_id(channel)}
            end)
        }

        next_state =
          case state.http_module.post(
                 state.api_base_url,
                 "/rooms/#{URI.encode_www_form(state.room_id)}/publications",
                 payload
               ) do
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

  def update(:wizard_escape, state) do
    if state.wizard_step == 0 do
      {Nav.transition(state, :lobby, app_pid: self()), []}
    else
      {%{state | wizard_step: state.wizard_step - 1, wizard_cursor: 0}, []}
    end
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

  def handle_info({:fetch_room, room_id}, state) do
    next_state =
      case state.http_module.get(state.api_base_url, "/rooms/#{URI.encode_www_form(room_id)}") do
        {:ok, %{"data" => snapshot}} ->
          Lobby.upsert_row(state, Lobby.row_from_snapshot(room_id, snapshot))

        {:error, :not_found} ->
          Lobby.upsert_row(state, Lobby.fetch_error_row(room_id))

        {:error, _reason} ->
          Lobby.upsert_row(state, Lobby.fetch_error_row(room_id))
      end

    {next_state, []}
  end

  def handle_info(:fetch_wizard_targets, state) do
    next_state =
      case state.http_module.get(state.api_base_url, "/targets") do
        {:ok, %{"data" => targets}} ->
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

  def handle_info(:fetch_wizard_policies, state) do
    next_state =
      case state.http_module.get(state.api_base_url, "/policies") do
        {:ok, %{"data" => policies}} ->
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

  def handle_info(:fetch_publication_plan, state) do
    next_state =
      case state.http_module.get(
             state.api_base_url,
             "/rooms/#{URI.encode_www_form(state.room_id)}/publication_plan"
           ) do
        {:ok, %{"data" => plan}} ->
          %{state | publish_plan: plan}

        {:error, reason} ->
          Model.set_status(state, "Plan fetch failed: #{inspect(reason)}", :error)
      end

    {next_state, []}
  end

  def handle_info(:refresh_auth_state, state) do
    {%{state | publish_auth_state: state.auth_module.load_all()}, []}
  end

  def handle_info({:run_room_result, room_id, {:ok, _snapshot}}, state) do
    next_state =
      if state.room_id == room_id do
        state
        |> Nav.refresh_room_snapshot()
        |> Model.set_status("Room run completed", :info)
      else
        state
      end

    {next_state, []}
  end

  def handle_info({:run_room_result, room_id, {:error, reason}}, state) do
    next_state =
      if state.room_id == room_id do
        Model.set_status(state, "Room run failed: #{inspect(reason)}", :error)
      else
        state
      end

    {next_state, []}
  end

  def handle_info({:event_log_update, entries, cursor}, state) do
    formatted =
      entries
      |> Enum.map(&Projection.format_event_entry/1)
      |> Enum.reverse()

    lines =
      (formatted ++ state.event_log_lines)
      |> Enum.uniq()
      |> Enum.take(200)

    {%{state | event_log_lines: lines, event_log_cursor: cursor}, []}
  end

  def handle_info({:event_log_warning, reason}, state) do
    {Model.set_status(state, "Event log warning: #{inspect(reason)}", :warn), []}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    cond do
      pid == state.event_log_poller_pid and reason in [:normal, :shutdown] ->
        {%{state | event_log_poller_pid: nil}, []}

      pid == state.embedded and reason in [:normal, :shutdown] ->
        {%{state | embedded: nil}, []}

      true ->
        {state, []}
    end
  end

  def handle_info(_msg, state), do: {state, []}

  @impl true
  def view(state) do
    screen_module(state).render(state)
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
      with {:ok, _response} <- state.http_module.post(state.api_base_url, "/rooms", payload),
           :ok <- config_add_room(state.config_module, room_id, state.api_base_url) do
        start_room_run_async(state, room_id)

        state
        |> Nav.transition(:room, room_id: room_id, app_pid: self())
        |> Model.set_status("Created room #{room_id}; run started in background", :info)
      else
        {:error, reason} ->
          Model.set_status(state, "Room creation failed: #{inspect(reason)}", :error)
      end

    {next_state, []}
  end

  defp screen_module(%{active_screen: :lobby}), do: Lobby
  defp screen_module(%{active_screen: :conflict}), do: Conflict
  defp screen_module(%{active_screen: :publish}), do: Publish
  defp screen_module(%{active_screen: :wizard}), do: Wizard
  defp screen_module(_state), do: Room

  defp identity(%Model{} = state) do
    %Identity{
      participant_id: state.participant_id,
      participant_role: state.participant_role,
      authority_level: state.authority_level,
      display_name: state.participant_id
    }
  end

  defp context_id(object), do: Map.get(object, "context_id") || Map.get(object, :context_id)
  defp object_type(object), do: Map.get(object, "object_type") || Map.get(object, :object_type)

  defp drop_last_grapheme(value) do
    value
    |> String.graphemes()
    |> Enum.drop(-1)
    |> Enum.join()
  end

  defp empty_room_enter(state) do
    case Model.selected_context(state) do
      nil ->
        {Model.set_status(state, "Type a message or select a conflict", :warn), []}

      selected ->
        enter_selected_context(state, selected)
    end
  end

  defp enter_selected_context(state, selected) do
    if Projection.conflict?(selected) do
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
    http_module = state.http_module
    api_base_url = state.api_base_url

    spawn(fn ->
      result =
        http_module.post(
          api_base_url,
          "/rooms/#{URI.encode_www_form(room_id)}/run",
          %{}
        )

      send(caller, {:run_room_result, room_id, result})
    end)

    :ok
  end

  defp config_add_room(config_module, room_id, api_base_url) do
    cond do
      function_exported?(config_module, :add_room, 2) ->
        config_module.add_room(room_id, api_base_url)

      function_exported?(config_module, :add_room, 1) ->
        config_module.add_room(room_id)

      true ->
        {:error, :config_module_missing_add_room}
    end
  end

  defp config_remove_room(config_module, room_id, api_base_url) do
    cond do
      function_exported?(config_module, :remove_room, 2) ->
        config_module.remove_room(room_id, api_base_url)

      function_exported?(config_module, :remove_room, 1) ->
        config_module.remove_room(room_id)

      true ->
        {:error, :config_module_missing_remove_room}
    end
  end

  defp submit_room_chat(state, text) do
    submit_attrs = Identity.to_submit_attrs(identity(state), room_submit_attrs(text, state))

    case state.embedded_module.submit_chat(state.embedded, submit_attrs) do
      {:ok, _contribution} ->
        next_state =
          state
          |> Model.clear_input()
          |> Nav.refresh_room_snapshot()
          |> Model.set_status("Submitted chat message", :info)

        {next_state, []}

      {:error, reason} ->
        {Model.set_status(state, "Submit failed: #{inspect(reason)}", :error), []}
    end
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

  defp conflict_title(object, fallback) do
    Map.get(object || %{}, "title") || fallback
  end

  defp conflict_id(object, fallback) do
    Map.get(object || %{}, "context_id") || fallback
  end

  defp same_target?(left, right) do
    (left["target_id"] || left[:target_id]) == (right["target_id"] || right[:target_id])
  end

  defp put_nested_binding(bindings, channel, field, value) do
    Map.update(bindings, channel, %{field => value}, &Map.put(&1, field, value))
  end
end
