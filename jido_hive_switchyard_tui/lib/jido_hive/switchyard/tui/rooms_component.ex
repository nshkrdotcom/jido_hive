defmodule JidoHive.Switchyard.TUI.RoomsComponent do
  @moduledoc false

  @behaviour Workbench.Component

  alias ExRatatui.Event
  alias JidoHive.Switchyard.TUI.{RoomsRuntime, RoomsView, State}
  alias JidoHivePublications
  alias JidoHiveSurface
  alias Workbench.{Cmd, Keymap}

  @app_id "jido-hive.rooms"

  def app_id, do: @app_id

  @impl true
  def init(%{context: context} = props, _ctx) do
    state =
      State.new(
        client_module: Map.get(context, :client_module, JidoHiveSurface),
        publications_module: Map.get(context, :publications_module, JidoHivePublications)
      )

    room_id = Map.get(context, :room_id)
    next_state = %{state | room_id: room_id}

    if present?(room_id) do
      {:ok, State.set_status(next_state, "Loading room workspace...", :info),
       [RoomsRuntime.load_room_workspace(props, next_state, room_id)]}
    else
      next_state =
        %{next_state | screen: :rooms} |> State.set_status("Loading saved rooms...", :info)

      {:ok, next_state, [RoomsRuntime.load_rooms(props, next_state)]}
    end
  end

  @impl true
  def update({:key, %Event.Key{} = event}, %State{} = state, props, ctx) do
    case event_to_msg(event, state) do
      :ignore -> :unhandled
      msg -> update(msg, state, props, ctx)
    end
  end

  def update(:room_prev, %State{} = state, _props, _ctx),
    do: {:ok, State.move_room_cursor(state, -1), []}

  def update(:room_next, %State{} = state, _props, _ctx),
    do: {:ok, State.move_room_cursor(state, 1), []}

  def update(:context_prev, %State{} = state, _props, _ctx),
    do: {:ok, State.move_context_cursor(state, -1), []}

  def update(:context_next, %State{} = state, _props, _ctx),
    do: {:ok, State.move_context_cursor(state, 1), []}

  def update(:open_selected_room, %State{} = state, props, _ctx) do
    case State.selected_room(state) do
      nil ->
        {:ok, State.set_status(state, "No room selected.", :warn), []}

      %{fetch_error: true} ->
        {:ok, State.set_status(state, "Selected room could not be loaded.", :error), []}

      room ->
        room_id = room.id

        next_state =
          %{state | room_id: room_id} |> State.set_status("Loading room workspace...", :info)

        {:ok, next_state, [RoomsRuntime.load_room_workspace(props, state, room_id)]}
    end
  end

  def update(:leave_component, %State{} = state, _props, _ctx) do
    {:ok, state, [Cmd.message({:workbench_root, :back})]}
  end

  def update(:back_to_rooms, %State{} = state, _props, _ctx) do
    {:ok, State.back_to_rooms(state) |> State.set_status("Returned to room list.", :info), []}
  end

  def update(:close_overlay, %State{} = state, _props, _ctx) do
    {:ok, State.close_overlay(state) |> State.set_status("Closed overlay.", :info), []}
  end

  def update(:refresh_room, %State{room_id: room_id} = state, props, _ctx)
      when is_binary(room_id) do
    next_state = State.set_status(state, "Refreshing room workspace...", :info)
    {:ok, next_state, [RoomsRuntime.load_room_workspace(props, state, room_id)]}
  end

  def update(:refresh_room, _state, _props, _ctx), do: :unhandled

  def update(
        :open_provenance,
        %State{room_id: room_id, selected_context_id: context_id} = state,
        props,
        _ctx
      )
      when is_binary(room_id) and is_binary(context_id) do
    next_state = State.set_status(state, "Loading provenance...", :info)
    {:ok, next_state, [RoomsRuntime.load_provenance(props, state, room_id, context_id)]}
  end

  def update(:open_provenance, _state, _props, _ctx), do: :unhandled

  def update(:open_publish, %State{room_id: room_id} = state, props, _ctx)
      when is_binary(room_id) do
    next_state = State.set_status(state, "Loading publication workspace...", :info)
    {:ok, next_state, [RoomsRuntime.load_publication_workspace(props, state, room_id)]}
  end

  def update(:open_publish, _state, _props, _ctx), do: :unhandled

  def update(:submit_draft, %State{room_id: room_id, draft: draft} = state, props, _ctx)
      when is_binary(room_id) and is_binary(draft) and draft != "" do
    next_state = State.set_status(state, "Submitting steering message...", :info)
    {:ok, next_state, [RoomsRuntime.submit_draft(props, state, draft)]}
  end

  def update(:submit_draft, _state, _props, _ctx), do: :unhandled

  def update(
        :publish_now,
        %State{room_id: room_id, publication_workspace: workspace} = state,
        props,
        _ctx
      )
      when is_binary(room_id) and is_map(workspace) do
    next_state = State.set_status(state, "Publishing room output...", :info)
    {:ok, next_state, [RoomsRuntime.publish(props, state)]}
  end

  def update(:publish_now, _state, _props, _ctx), do: :unhandled

  def update({:append_draft, text}, %State{} = state, _props, _ctx),
    do: {:ok, State.append_draft(state, text), []}

  def update(:draft_backspace, %State{} = state, _props, _ctx),
    do: {:ok, State.draft_backspace(state), []}

  def update(:clear_active_input, %State{} = state, _props, _ctx),
    do: {:ok, State.clear_draft(state), []}

  def update({:append_publish_text, text}, %State{} = state, _props, _ctx),
    do: {:ok, State.append_publish_text(state, text), []}

  def update(:publish_backspace, %State{} = state, _props, _ctx),
    do: {:ok, State.publish_backspace(state), []}

  def update(:next_publish_field, %State{} = state, _props, _ctx),
    do: {:ok, State.next_publish_field_cursor(state), []}

  def update({:rooms_loaded, rooms}, %State{} = state, _props, _ctx) do
    {:ok, State.put_rooms(state, rooms) |> State.set_status("Loaded saved rooms.", :info), []}
  end

  def update({:room_workspace_loaded, workspace}, %State{} = state, _props, _ctx) do
    {:ok, State.open_room(state, workspace) |> State.set_status("Loaded room workspace.", :info),
     []}
  end

  def update({:provenance_loaded, provenance}, %State{} = state, _props, _ctx) do
    {:ok,
     State.open_overlay(state, :provenance, provenance)
     |> State.set_status("Loaded provenance.", :info), []}
  end

  def update({:publication_workspace_loaded, workspace}, %State{} = state, _props, _ctx) do
    next_state =
      state
      |> State.set_publication_workspace(workspace)
      |> State.open_overlay(:publish, workspace)
      |> State.set_status("Loaded publication workspace.", :info)

    {:ok, next_state, []}
  end

  def update({:steering_submitted, {:ok, _result}}, %State{room_id: room_id} = state, props, _ctx) do
    next_state =
      state
      |> State.clear_draft()
      |> State.set_status("Steering message submitted.", :info)

    {:ok, next_state, [RoomsRuntime.load_room_workspace(props, next_state, room_id)]}
  end

  def update({:published, {:ok, _result}}, %State{room_id: room_id} = state, props, _ctx) do
    next_state =
      state
      |> State.close_overlay()
      |> State.set_status("Publication submitted.", :info)

    {:ok, next_state, [RoomsRuntime.load_room_workspace(props, next_state, room_id)]}
  end

  def update({failure, reason}, %State{} = state, _props, _ctx)
      when failure in [
             :rooms_load_failed,
             :room_workspace_load_failed,
             :provenance_failed,
             :publication_workspace_failed
           ] do
    {:ok, State.set_status(state, failure_message(failure, reason), :error), []}
  end

  def update({:steering_submitted, {:error, reason}}, %State{} = state, _props, _ctx) do
    {:ok, State.set_status(state, "Steering submit failed: #{inspect(reason)}", :error), []}
  end

  def update({:published, {:error, reason}}, %State{} = state, _props, _ctx) do
    {:ok, State.set_status(state, "Publish failed: #{inspect(reason)}", :error), []}
  end

  def update(_msg, _state, _props, _ctx), do: :unhandled

  @impl true
  def handle_info(msg, %State{} = state, props, ctx), do: update(msg, state, props, ctx)

  @impl true
  def render(%State{} = state, _props, _ctx), do: RoomsView.node(state)

  @impl true
  def render_accessible(_state, _props, _ctx), do: :unsupported

  @impl true
  def keymap(%State{screen: :rooms}, _props, _ctx) do
    [
      binding(:room_prev, "up", [], "Select previous room", :room_prev),
      binding(:room_next, "down", [], "Select next room", :room_next),
      binding(:open_selected_room, "enter", [], "Open room", :open_selected_room),
      binding(:leave_component, "esc", [], "Back", :leave_component)
    ]
  end

  def keymap(%State{screen: :room, overlay: %{kind: :publish}}, _props, _ctx) do
    [
      binding(:publish_now, "enter", [], "Publish", :publish_now),
      binding(:close_overlay, "esc", [], "Close overlay", :close_overlay),
      binding(:next_publish_field, "tab", [], "Next publish field", :next_publish_field),
      binding(:publish_backspace, "backspace", [], "Delete publish text", :publish_backspace)
    ]
  end

  def keymap(%State{screen: :room, overlay: %{kind: :provenance}}, _props, _ctx) do
    [binding(:close_overlay, "esc", [], "Close overlay", :close_overlay)]
  end

  def keymap(%State{screen: :room}, _props, _ctx) do
    [
      binding(:context_prev, "up", [], "Select previous context", :context_prev),
      binding(:context_next, "down", [], "Select next context", :context_next),
      binding(:submit_draft, "enter", [], "Submit draft", :submit_draft),
      binding(:back_to_rooms, "esc", [], "Back to rooms", :back_to_rooms),
      binding(:open_provenance, "e", ["ctrl"], "Open provenance", :open_provenance),
      binding(:open_publish, "p", ["ctrl"], "Open publish", :open_publish),
      binding(:refresh_room, "r", ["ctrl"], "Refresh room", :refresh_room),
      binding({:append_draft, "\n"}, "j", ["ctrl"], "New line", {:append_draft, "\n"}),
      binding(:clear_active_input, "c", ["ctrl"], "Clear input", :clear_active_input),
      binding(:draft_backspace, "backspace", [], "Delete draft text", :draft_backspace)
    ]
  end

  @impl true
  def actions(_state, _props, _ctx), do: []

  @impl true
  def subscriptions(_state, _props, _ctx), do: []

  defp event_to_msg(%Event.Key{code: code, modifiers: []}, %State{
         screen: :room,
         overlay: %{kind: :publish}
       })
       when is_binary(code) and code != "" do
    if printable?(code), do: {:append_publish_text, code}, else: :ignore
  end

  defp event_to_msg(%Event.Key{code: code, modifiers: []}, %State{screen: :room, overlay: nil})
       when is_binary(code) and code != "" do
    if printable?(code), do: {:append_draft, code}, else: :ignore
  end

  defp event_to_msg(_event, _state), do: :ignore

  defp binding(id, code, modifiers, description, message) do
    Keymap.binding(
      id: id,
      keys: [Keymap.key(code, modifiers)],
      description: description,
      message: message
    )
  end

  defp failure_message(:rooms_load_failed, reason), do: "Room list failed: #{inspect(reason)}"

  defp failure_message(:room_workspace_load_failed, reason),
    do: "Room workspace failed: #{inspect(reason)}"

  defp failure_message(:provenance_failed, reason), do: "Provenance failed: #{inspect(reason)}"

  defp failure_message(:publication_workspace_failed, reason),
    do: "Publication workspace failed: #{inspect(reason)}"

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp printable?(code), do: String.length(code) == 1 and code not in ["\t", "\n", "\r"]
end
