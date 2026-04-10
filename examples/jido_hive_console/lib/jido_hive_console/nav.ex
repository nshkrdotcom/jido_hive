defmodule JidoHiveConsole.Nav do
  @moduledoc false

  alias JidoHiveConsole.{Identity, Model, Projection}
  alias JidoHiveConsole.Screens.Lobby

  @spec transition(Model.t(), :lobby | :room | :conflict | :publish | :wizard, keyword()) ::
          Model.t()
  def transition(%Model{} = state, destination, opts \\ []) do
    case destination do
      :lobby -> transition_to_lobby(state, opts)
      :room -> transition_to_room(state, opts)
      :conflict -> transition_to_conflict(state)
      :publish -> transition_to_publish(state, opts)
      :wizard -> transition_to_wizard(state, opts)
    end
  end

  @spec apply_room_snapshot(Model.t(), map()) :: Model.t()
  def apply_room_snapshot(%Model{} = state, snapshot) when is_map(snapshot) do
    state
    |> Model.apply_snapshot(snapshot)
    |> sync_event_log_from_snapshot()
  end

  @spec refresh_room_snapshot(Model.t()) :: Model.t()
  def refresh_room_snapshot(%Model{room_id: nil} = state), do: state

  def refresh_room_snapshot(%Model{embedded: nil} = state), do: state

  def refresh_room_snapshot(%Model{} = state) do
    snapshot = state.embedded_module.snapshot(state.embedded)
    apply_room_snapshot(state, snapshot)
  rescue
    error ->
      state
      |> Map.put(:sync_error, true)
      |> Model.set_status("Room snapshot failed: #{Exception.message(error)}", :error)
  catch
    :exit, reason ->
      state
      |> Map.put(:sync_error, true)
      |> Model.set_status("Room snapshot failed: #{inspect(reason)}", :error)
  end

  defp transition_to_lobby(%Model{} = state, opts) do
    stop_room_processes(state)
    room_ids = state.operator_module.list_saved_rooms(state.api_base_url)
    app_pid = Keyword.get(opts, :app_pid)

    next_state =
      build_state(state, %{
        active_screen: :lobby,
        lobby_rooms: Enum.map(room_ids, &Lobby.placeholder_row/1),
        lobby_loading: room_ids != [],
        status_line: "Ready",
        status_severity: :info,
        help_visible: auto_open_help?(state, :lobby)
      })

    Enum.each(room_ids, fn room_id ->
      if is_pid(app_pid), do: send(app_pid, {:fetch_room, room_id})
    end)

    next_state
  end

  defp transition_to_room(%Model{} = state, opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    preserve_existing = Keyword.get(opts, :preserve_existing, false)

    {embedded, poller_pid} =
      room_processes_for_transition(state, room_id, preserve_existing, opts)

    room_snapshot = load_room_session_snapshot(state, room_id, embedded)
    fetch_error = Map.get(room_snapshot, "last_error")

    {embedded, poller_pid} =
      if fetch_error in [:not_found, :room_not_found] do
        stop_poller(poller_pid)
        stop_embedded(state.embedded_module, embedded)
        {nil, nil}
      else
        {embedded, poller_pid}
      end

    next_state =
      state
      |> build_state(%{
        active_screen: :room,
        room_id: room_id,
        embedded: embedded,
        event_log_poller_pid: poller_pid,
        snapshot: room_snapshot,
        sync_error: not is_nil(fetch_error),
        help_visible: if(fetch_error, do: false, else: auto_open_help?(state, :room)),
        status_line: room_fetch_status(room_id, fetch_error),
        status_severity: room_fetch_severity(fetch_error)
      })

    if fetch_error do
      next_state
    else
      apply_room_snapshot(next_state, room_snapshot)
    end
  end

  defp transition_to_conflict(%Model{} = state) do
    case Model.selected_context(state) do
      nil ->
        Model.set_status(state, "No context object selected", :error)

      conflict_left ->
        conflict_right = find_conflict_partner(conflict_left, state.snapshot)

        build_room_screen_state(state, %{
          active_screen: :conflict,
          conflict_left: conflict_left,
          conflict_right: conflict_right,
          conflict_input_buf: "",
          help_visible: auto_open_help?(state, :conflict)
        })
    end
  end

  defp transition_to_publish(%Model{} = state, opts) do
    app_pid = Keyword.get(opts, :app_pid)

    if is_pid(app_pid) do
      send(app_pid, :fetch_publication_plan)
      send(app_pid, :refresh_auth_state)
    end

    build_room_screen_state(state, %{
      active_screen: :publish,
      publish_plan: nil,
      publish_selected: [],
      publish_cursor: 0,
      publish_bindings: %{},
      publish_auth_state: %{},
      help_visible: auto_open_help?(state, :publish)
    })
  end

  defp transition_to_wizard(%Model{} = state, opts) do
    app_pid = Keyword.get(opts, :app_pid)

    if is_pid(app_pid) do
      send(app_pid, :fetch_wizard_targets)
      send(app_pid, :fetch_wizard_policies)
    end

    build_state(state, %{
      active_screen: :wizard,
      wizard_step: 0,
      wizard_fields: %{},
      wizard_cursor: 0,
      wizard_available_targets: [],
      wizard_targets_state: :loading,
      wizard_available_policies: [],
      wizard_policies_state: :loading,
      help_visible: auto_open_help?(state, :wizard)
    })
  end

  defp build_state(%Model{} = state, overrides) do
    preserved =
      %{
        api_base_url: state.api_base_url,
        tenant_id: state.tenant_id,
        actor_id: state.actor_id,
        participant_id: state.participant_id,
        participant_role: state.participant_role,
        authority_level: state.authority_level,
        poll_interval_ms: state.poll_interval_ms,
        screen_width: state.screen_width,
        screen_height: state.screen_height,
        embedded_module: state.embedded_module,
        operator_module: state.operator_module,
        event_log_poller_module: state.event_log_poller_module,
        help_seen: state.help_seen,
        room_input_ref: state.room_input_ref,
        conflict_input_ref: state.conflict_input_ref,
        wizard_brief_input_ref: state.wizard_brief_input_ref,
        publish_input_ref: state.publish_input_ref
      }
      |> Map.merge(overrides)

    struct(Model, Map.merge(Map.from_struct(%Model{}), preserved))
  end

  defp build_room_screen_state(%Model{} = state, overrides) do
    preserved =
      %{
        embedded: state.embedded,
        embedded_module: state.embedded_module,
        event_log_poller_pid: state.event_log_poller_pid,
        room_id: state.room_id,
        room_flow: state.room_flow,
        snapshot: state.snapshot,
        event_log_lines: state.event_log_lines,
        event_log_cursor: state.event_log_cursor,
        sync_error: state.sync_error,
        pending_room_submit: state.pending_room_submit,
        pending_room_run: state.pending_room_run,
        status_line: state.status_line,
        status_severity: state.status_severity,
        status_animation_tick: state.status_animation_tick
      }

    build_state(state, Map.merge(preserved, overrides))
  end

  defp auto_open_help?(state, screen) do
    not MapSet.member?(state.help_seen, screen)
  end

  defp stop_room_processes(%Model{} = state) do
    stop_poller(state.event_log_poller_pid)
    stop_embedded(state.embedded_module, state.embedded)
  end

  defp stop_poller(pid) when is_pid(pid), do: Process.exit(pid, :shutdown)
  defp stop_poller(_pid), do: :ok

  defp stop_embedded(_module, nil), do: :ok

  defp stop_embedded(module, embedded) do
    if function_exported?(module, :shutdown, 1) do
      module.shutdown(embedded)
    else
      Process.exit(embedded, :shutdown)
    end
  end

  defp ensure_embedded(%Model{} = state, room_id, opts) do
    case Keyword.get(opts, :embedded) do
      nil ->
        embedded_opts =
          state
          |> identity()
          |> Identity.to_embedded_opts()
          |> Keyword.merge(
            room_id: room_id,
            api_base_url: state.api_base_url,
            poll_interval_ms: state.poll_interval_ms
          )

        {:ok, embedded} = state.embedded_module.start_link(embedded_opts)
        embedded

      embedded ->
        embedded
    end
  end

  defp sync_event_log_from_snapshot(%Model{} = state) do
    timeline = Map.get(state.snapshot, "timeline") || Map.get(state.snapshot, :timeline) || []

    lines =
      timeline
      |> Enum.map(&Projection.format_event_entry/1)
      |> Enum.reverse()
      |> Enum.take(200)

    cursor =
      Map.get(state.snapshot, "next_cursor") || Map.get(state.snapshot, :next_cursor) ||
        timeline_cursor(timeline)

    %{state | event_log_lines: lines, event_log_cursor: cursor}
  end

  defp timeline_cursor([]), do: nil

  defp timeline_cursor(timeline) do
    timeline
    |> List.last()
    |> then(fn entry ->
      Map.get(entry, "cursor") || Map.get(entry, :cursor) ||
        Map.get(entry, "event_id") || Map.get(entry, :event_id)
    end)
  end

  defp identity(%Model{} = state) do
    %Identity{
      participant_id: state.participant_id,
      participant_role: state.participant_role,
      authority_level: state.authority_level,
      display_name: state.participant_id
    }
  end

  defp find_conflict_partner(conflict_left, snapshot) do
    conflict_left
    |> conflict_edges(snapshot)
    |> Enum.find_value(&conflict_partner_from_edge(&1, snapshot)) ||
      %{
        "context_id" => "unknown",
        "object_type" => "conflict_target",
        "title" => "[not in view]"
      }
  end

  defp conflict_edges(object, snapshot) do
    if has_adjacency?(object),
      do: adjacency_edges(object),
      else: relation_conflict_edges(object, snapshot)
  end

  defp has_adjacency?(object) do
    Map.has_key?(object, "adjacency") or Map.has_key?(object, :adjacency)
  end

  defp adjacency_edges(object) do
    adjacency = Map.get(object, "adjacency") || Map.get(object, :adjacency) || %{}
    outgoing = Map.get(adjacency, "outgoing") || Map.get(adjacency, :outgoing) || []
    incoming = Map.get(adjacency, "incoming") || Map.get(adjacency, :incoming) || []
    outgoing ++ incoming
  end

  defp relation_conflict_edges(object, snapshot) do
    object_id = Map.get(object, "context_id") || Map.get(object, :context_id)

    outgoing_relation_partner_edges(object) ++
      incoming_relation_partner_edges(snapshot, object_id)
  end

  defp outgoing_relation_partner_edges(object) do
    object
    |> relation_list()
    |> Enum.map(&partner_edge_from_outgoing_relation/1)
  end

  defp incoming_relation_partner_edges(snapshot, object_id) do
    snapshot
    |> context_objects()
    |> Enum.flat_map(&incoming_partner_edges_for_candidate(&1, object_id))
  end

  defp incoming_partner_edges_for_candidate(candidate, object_id) do
    source_id = Map.get(candidate, "context_id") || Map.get(candidate, :context_id)

    candidate
    |> relation_list()
    |> Enum.filter(&(relation_target_id(&1) == object_id))
    |> Enum.map(&partner_edge_from_incoming_relation(&1, source_id))
  end

  defp partner_edge_from_outgoing_relation(relation) do
    %{
      "type" => relation_type(relation),
      "partner_id" => relation_target_id(relation)
    }
  end

  defp partner_edge_from_incoming_relation(relation, source_id) do
    %{
      "type" => relation_type(relation),
      "partner_id" => source_id
    }
  end

  defp relation_list(object) do
    Map.get(object, "relations", Map.get(object, :relations, []))
  end

  defp relation_type(relation) do
    Map.get(relation, "relation") || Map.get(relation, :relation)
  end

  defp relation_target_id(relation) do
    Map.get(relation, "target_id") || Map.get(relation, :target_id)
  end

  defp context_objects(snapshot),
    do: Map.get(snapshot, "context_objects") || Map.get(snapshot, :context_objects) || []

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_keys(_other), do: %{}

  defp room_processes_for_transition(state, room_id, true, _opts)
       when state.room_id == room_id and not is_nil(state.embedded) do
    {state.embedded, nil}
  end

  defp room_processes_for_transition(state, room_id, _preserve_existing, opts) do
    stop_room_processes(state)
    embedded = ensure_embedded(state, room_id, opts)
    {embedded, nil}
  end

  defp load_room_session_snapshot(state, room_id, embedded) do
    case state.embedded_module.refresh(embedded) do
      {:ok, snapshot} ->
        safe_subscribe_room_session(state, embedded)
        stringify_keys(snapshot)

      {:error, reason} ->
        maybe_subscribe_room_session(state, embedded, reason)

        embedded
        |> state.embedded_module.snapshot()
        |> stringify_keys()
        |> Map.put("room_id", room_id)
        |> Map.put("last_error", reason)
        |> Map.put_new(
          "status",
          if(room_not_found?(reason), do: "not_found", else: "unavailable")
        )
        |> Map.put_new("context_objects", [])
        |> Map.put_new("timeline", [])
        |> Map.put_new("participants", [])
        |> Map.put_new("dispatch_state", %{"completed_slots" => 0, "total_slots" => 0})
    end
  rescue
    _error ->
      missing_or_unavailable_room_snapshot(room_id, :unavailable)
  end

  defp safe_subscribe_room_session(state, embedded) do
    :ok = state.embedded_module.subscribe(embedded)
  rescue
    _error -> :ok
  end

  defp maybe_subscribe_room_session(_state, _embedded, reason)
       when reason in [:not_found, :room_not_found],
       do: :ok

  defp maybe_subscribe_room_session(state, embedded, _reason),
    do: safe_subscribe_room_session(state, embedded)

  defp room_fetch_status(room_id, fetch_error) when fetch_error in [:not_found, :room_not_found],
    do: "Room #{room_id} was not found on this server"

  defp room_fetch_status(_room_id, fetch_error) when not is_nil(fetch_error),
    do: "Room could not be loaded: #{inspect(fetch_error)}"

  defp room_fetch_status(_room_id, _fetch_error), do: "Ready"

  defp room_fetch_severity(fetch_error) when is_nil(fetch_error), do: :info
  defp room_fetch_severity(_fetch_error), do: :error

  defp missing_or_unavailable_room_snapshot(room_id, reason) do
    %{
      "room_id" => room_id,
      "status" => if(room_not_found?(reason), do: "not_found", else: "unavailable"),
      "context_objects" => [],
      "timeline" => [],
      "participants" => [],
      "dispatch_state" => %{"completed_slots" => 0, "total_slots" => 0},
      "last_error" => reason
    }
  end

  defp conflict_partner_from_edge(edge, snapshot) do
    with true <- contradiction_edge?(edge),
         target_id when is_binary(target_id) <- conflict_target_id(edge) do
      find_context_object(snapshot, target_id) || missing_conflict_target(target_id)
    else
      _other -> nil
    end
  end

  defp contradiction_edge?(edge) do
    type = Map.get(edge, "type") || Map.get(edge, :type)
    type in ["contradicts", :contradicts]
  end

  defp conflict_target_id(edge) do
    Map.get(edge, "partner_id") || Map.get(edge, :partner_id) ||
      Map.get(edge, "target_id") || Map.get(edge, :target_id) ||
      Map.get(edge, "from_id") || Map.get(edge, :from_id)
  end

  defp find_context_object(snapshot, target_id) do
    Enum.find(context_objects(snapshot), fn object ->
      (Map.get(object, "context_id") || Map.get(object, :context_id)) == target_id
    end)
  end

  defp missing_conflict_target(target_id) do
    %{
      "context_id" => target_id,
      "object_type" => "conflict_target",
      "title" => "[not in view]"
    }
  end

  defp room_not_found?(:room_not_found), do: true
  defp room_not_found?(:not_found), do: true
  defp room_not_found?(_reason), do: false
end
