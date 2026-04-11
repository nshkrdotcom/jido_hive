defmodule JidoHive.Switchyard.TUI.RoomsMount do
  @moduledoc false

  @behaviour Switchyard.TUI.Mount

  alias JidoHive.Switchyard.TUI.{RoomsRuntime, RoomsView, State}
  alias JidoHiveSurface
  alias Switchyard.TUI.Model

  @app_id "jido-hive.rooms"

  @impl true
  def id, do: @app_id

  @impl true
  def init(opts) do
    State.new(client_module: Keyword.get(opts, :client_module, JidoHiveSurface))
  end

  @impl true
  def open(%Model{} = model, %State{} = state) do
    room_id = Map.get(model.context, :room_id)
    next_state = %{state | room_id: room_id}

    if present?(room_id) do
      {Model.set_status(model, "Loading room workspace...", :info), next_state,
       [RoomsRuntime.load_room_workspace(model, next_state, room_id)]}
    else
      {Model.set_status(model, "Loading saved rooms...", :info), %{next_state | screen: :rooms},
       [RoomsRuntime.load_rooms(model, next_state)]}
    end
  end

  @impl true
  def event_to_msg(%ExRatatui.Event.Key{code: "up"}, _model, %State{screen: :rooms}),
    do: {:msg, :room_prev}

  def event_to_msg(%ExRatatui.Event.Key{code: "down"}, _model, %State{screen: :rooms}),
    do: {:msg, :room_next}

  def event_to_msg(%ExRatatui.Event.Key{code: "up"}, _model, %State{screen: :room, overlay: nil}),
    do: {:msg, :context_prev}

  def event_to_msg(%ExRatatui.Event.Key{code: "down"}, _model, %State{screen: :room, overlay: nil}),
      do: {:msg, :context_next}

  def event_to_msg(%ExRatatui.Event.Key{code: "enter"}, _model, %State{screen: :rooms}),
    do: {:msg, :open_selected_room}

  def event_to_msg(
        %ExRatatui.Event.Key{code: "enter"},
        _model,
        %State{screen: :room, overlay: %{kind: :publish}}
      ),
      do: {:msg, :publish_now}

  def event_to_msg(
        %ExRatatui.Event.Key{code: "enter"},
        _model,
        %State{screen: :room, overlay: nil, draft: draft}
      )
      when is_binary(draft) and draft != "" do
    {:msg, :submit_draft}
  end

  def event_to_msg(%ExRatatui.Event.Key{code: "enter"}, _model, _state), do: :ignore

  def event_to_msg(
        %ExRatatui.Event.Key{code: "esc"},
        _model,
        %State{screen: :room, overlay: overlay}
      )
      when not is_nil(overlay),
      do: {:msg, :close_overlay}

  def event_to_msg(%ExRatatui.Event.Key{code: "esc"}, _model, %State{screen: :room}),
    do: {:msg, :back_to_rooms}

  def event_to_msg(
        %ExRatatui.Event.Key{code: "e", modifiers: ["ctrl"]},
        _model,
        %State{screen: :room, overlay: nil}
      ),
      do: {:msg, :open_provenance}

  def event_to_msg(
        %ExRatatui.Event.Key{code: "p", modifiers: ["ctrl"]},
        _model,
        %State{screen: :room, overlay: nil}
      ),
      do: {:msg, :open_publish}

  def event_to_msg(
        %ExRatatui.Event.Key{code: "r", modifiers: ["ctrl"]},
        _model,
        %State{screen: :room, overlay: nil}
      ),
      do: {:msg, :refresh_room}

  def event_to_msg(
        %ExRatatui.Event.Key{code: "j", modifiers: ["ctrl"]},
        _model,
        %State{screen: :room, overlay: nil}
      ),
      do: {:msg, {:append_draft, "\n"}}

  def event_to_msg(
        %ExRatatui.Event.Key{code: "c", modifiers: ["ctrl"]},
        _model,
        %State{screen: :room, overlay: nil}
      ),
      do: {:msg, :clear_active_input}

  def event_to_msg(
        %ExRatatui.Event.Key{code: "tab"},
        _model,
        %State{screen: :room, overlay: %{kind: :publish}}
      ),
      do: {:msg, :next_publish_field}

  def event_to_msg(
        %ExRatatui.Event.Key{code: "backspace"},
        _model,
        %State{screen: :room, overlay: %{kind: :publish}}
      ),
      do: {:msg, :publish_backspace}

  def event_to_msg(
        %ExRatatui.Event.Key{code: "backspace"},
        _model,
        %State{screen: :room, overlay: nil}
      ),
      do: {:msg, :draft_backspace}

  def event_to_msg(
        %ExRatatui.Event.Key{code: code, modifiers: []},
        _model,
        %State{screen: :room, overlay: %{kind: :publish}}
      )
      when is_binary(code) and code != "" do
    if printable?(code), do: {:msg, {:append_publish_text, code}}, else: :ignore
  end

  def event_to_msg(
        %ExRatatui.Event.Key{code: code, modifiers: []},
        _model,
        %State{screen: :room, overlay: nil}
      )
      when is_binary(code) and code != "" do
    if printable?(code), do: {:msg, {:append_draft, code}}, else: :ignore
  end

  def event_to_msg(%ExRatatui.Event.Key{}, _model, _state), do: :ignore

  @impl true
  def update(:room_prev, model, %State{} = state),
    do: {model, State.move_room_cursor(state, -1), []}

  def update(:room_next, model, %State{} = state),
    do: {model, State.move_room_cursor(state, 1), []}

  def update(:context_prev, model, %State{} = state),
    do: {model, State.move_context_cursor(state, -1), []}

  def update(:context_next, model, %State{} = state),
    do: {model, State.move_context_cursor(state, 1), []}

  def update(:open_selected_room, %Model{} = model, %State{} = state) do
    case State.selected_room(state) do
      nil ->
        {Model.set_status(model, "No room selected.", :warn), state, []}

      %{fetch_error: true} ->
        {Model.set_status(model, "Selected room could not be loaded.", :error), state, []}

      room ->
        room_id = room.room_id

        {Model.set_status(model, "Loading room workspace...", :info), %{state | room_id: room_id},
         [RoomsRuntime.load_room_workspace(model, state, room_id)]}
    end
  end

  def update(:back_to_rooms, model, %State{} = state) do
    {Model.set_status(model, "Returned to room list.", :info), State.back_to_rooms(state), []}
  end

  def update(:close_overlay, model, %State{} = state) do
    {Model.set_status(model, "Closed overlay.", :info), State.close_overlay(state), []}
  end

  def update(:refresh_room, %Model{} = model, %State{room_id: room_id} = state)
      when is_binary(room_id) do
    {Model.set_status(model, "Refreshing room workspace...", :info), state,
     [RoomsRuntime.load_room_workspace(model, state, room_id)]}
  end

  def update(:refresh_room, model, state), do: {model, state, []}

  def update(
        :open_provenance,
        %Model{} = model,
        %State{room_id: room_id, selected_context_id: context_id} = state
      )
      when is_binary(room_id) and is_binary(context_id) do
    {Model.set_status(model, "Loading provenance...", :info), state,
     [RoomsRuntime.load_provenance(model, state, room_id, context_id)]}
  end

  def update(:open_provenance, model, state), do: {model, state, []}

  def update(:open_publish, %Model{} = model, %State{room_id: room_id} = state)
      when is_binary(room_id) do
    {Model.set_status(model, "Loading publication workspace...", :info), state,
     [RoomsRuntime.load_publication_workspace(model, state, room_id)]}
  end

  def update(:open_publish, model, state), do: {model, state, []}

  def update(:submit_draft, %Model{} = model, %State{room_id: room_id, draft: draft} = state)
      when is_binary(room_id) and is_binary(draft) and draft != "" do
    {Model.set_status(model, "Submitting steering message...", :info), state,
     [RoomsRuntime.submit_draft(model, state, draft)]}
  end

  def update(:submit_draft, model, state), do: {model, state, []}

  def update(
        :publish_now,
        %Model{} = model,
        %State{room_id: room_id, publication_workspace: workspace} = state
      )
      when is_binary(room_id) and is_map(workspace) do
    {Model.set_status(model, "Publishing room output...", :info), state,
     [RoomsRuntime.publish(model, state)]}
  end

  def update(:publish_now, model, state), do: {model, state, []}

  def update({:append_draft, text}, model, %State{} = state) do
    {model, State.append_draft(state, text), []}
  end

  def update(:draft_backspace, model, %State{} = state) do
    {model, State.draft_backspace(state), []}
  end

  def update(:clear_active_input, model, %State{} = state) do
    {model, State.clear_draft(state), []}
  end

  def update({:append_publish_text, text}, model, %State{} = state) do
    {model, State.append_publish_text(state, text), []}
  end

  def update(:publish_backspace, model, %State{} = state) do
    {model, State.publish_backspace(state), []}
  end

  def update(:next_publish_field, model, %State{} = state) do
    {model, State.next_publish_field_cursor(state), []}
  end

  def update({:rooms_loaded, rooms}, %Model{} = model, %State{} = state) do
    {Model.set_status(model, "Loaded saved rooms.", :info), State.put_rooms(state, rooms), []}
  end

  def update({:room_workspace_loaded, workspace}, %Model{} = model, %State{} = state) do
    {Model.set_status(model, "Loaded room workspace.", :info), State.open_room(state, workspace),
     []}
  end

  def update({:provenance_loaded, provenance}, %Model{} = model, %State{} = state) do
    {Model.set_status(model, "Loaded provenance.", :info),
     State.open_overlay(state, :provenance, provenance), []}
  end

  def update({:publication_workspace_loaded, workspace}, %Model{} = model, %State{} = state) do
    next_state =
      state
      |> State.set_publication_workspace(workspace)
      |> State.open_overlay(:publish, workspace)

    {Model.set_status(model, "Loaded publication workspace.", :info), next_state, []}
  end

  def update(
        {:steering_submitted, {:ok, _result}},
        %Model{} = model,
        %State{room_id: room_id} = state
      ) do
    next_state = State.clear_draft(state)

    {Model.set_status(model, "Steering message submitted.", :info), next_state,
     [RoomsRuntime.load_room_workspace(model, next_state, room_id)]}
  end

  def update({:published, {:ok, _result}}, %Model{} = model, %State{room_id: room_id} = state) do
    next_state = State.close_overlay(state)

    {Model.set_status(model, "Publication submitted.", :info), next_state,
     [RoomsRuntime.load_room_workspace(model, next_state, room_id)]}
  end

  def update({failure, reason}, %Model{} = model, %State{} = state)
      when failure in [
             :rooms_load_failed,
             :room_workspace_load_failed,
             :provenance_failed,
             :publication_workspace_failed
           ] do
    {Model.set_status(model, failure_message(failure, reason), :error), state, []}
  end

  def update({:steering_submitted, {:error, reason}}, %Model{} = model, %State{} = state) do
    {Model.set_status(model, "Steering submit failed: #{inspect(reason)}", :error), state, []}
  end

  def update({:published, {:error, reason}}, %Model{} = model, %State{} = state) do
    {Model.set_status(model, "Publish failed: #{inspect(reason)}", :error), state, []}
  end

  def update(_msg, _model, _state), do: :unhandled

  @impl true
  def render(%Model{} = model, %ExRatatui.Frame{} = frame, %State{} = state) do
    RoomsView.widgets(model, frame, state)
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
