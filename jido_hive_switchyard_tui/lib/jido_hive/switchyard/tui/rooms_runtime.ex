defmodule JidoHive.Switchyard.TUI.RoomsRuntime do
  @moduledoc false

  alias JidoHive.Switchyard.TUI.State
  alias Workbench.Cmd

  @spec load_rooms(map(), State.t()) :: Workbench.Cmd.t()
  def load_rooms(props, %State{} = state) do
    Cmd.async(
      fn ->
        state.client_module.list_rooms(Map.fetch!(props.context, :api_base_url),
          operator_module: Map.get(props.context, :operator_module)
        )
      end,
      fn
        rooms when is_list(rooms) -> {:rooms_loaded, rooms}
        other -> {:rooms_load_failed, other}
      end
    )
  end

  @spec load_room_workspace(map(), State.t(), String.t()) :: Workbench.Cmd.t()
  def load_room_workspace(props, %State{} = state, room_id) when is_binary(room_id) do
    Cmd.async(
      fn ->
        state.client_module.load_room_workspace(Map.fetch!(props.context, :api_base_url), room_id,
          operator_module: Map.get(props.context, :operator_module),
          selected_context_id: state.selected_context_id,
          participant_id: Map.get(props.context, :participant_id)
        )
      end,
      fn
        workspace when is_map(workspace) -> {:room_workspace_loaded, workspace}
        other -> {:room_workspace_load_failed, other}
      end
    )
  end

  @spec load_provenance(map(), State.t(), String.t(), String.t()) :: Workbench.Cmd.t()
  def load_provenance(props, %State{} = state, room_id, context_id)
      when is_binary(room_id) and is_binary(context_id) do
    Cmd.async(
      fn ->
        state.client_module.load_provenance(
          Map.fetch!(props.context, :api_base_url),
          room_id,
          context_id,
          operator_module: Map.get(props.context, :operator_module)
        )
      end,
      fn
        {:ok, provenance} -> {:provenance_loaded, provenance}
        other -> {:provenance_failed, other}
      end
    )
  end

  @spec load_publication_workspace(map(), State.t(), String.t()) :: Workbench.Cmd.t()
  def load_publication_workspace(props, %State{} = state, room_id)
      when is_binary(room_id) do
    Cmd.async(
      fn ->
        state.client_module.load_publication_workspace(
          Map.fetch!(props.context, :api_base_url),
          room_id,
          Map.fetch!(props.context, :subject),
          operator_module: Map.get(props.context, :operator_module)
        )
      end,
      fn
        workspace when is_map(workspace) -> {:publication_workspace_loaded, workspace}
        other -> {:publication_workspace_failed, other}
      end
    )
  end

  @spec submit_draft(map(), State.t(), String.t()) :: Workbench.Cmd.t()
  def submit_draft(props, %State{} = state, draft) when is_binary(draft) do
    identity = %{
      participant_id: Map.fetch!(props.context, :participant_id),
      participant_role: Map.fetch!(props.context, :participant_role),
      authority_level: Map.fetch!(props.context, :authority_level)
    }

    Cmd.async(
      fn ->
        state.client_module.submit_steering(
          Map.fetch!(props.context, :api_base_url),
          state.room_id,
          identity,
          draft,
          room_session_module: Map.get(props.context, :room_session_module)
        )
      end,
      &{:steering_submitted, &1}
    )
  end

  @spec publish(map(), State.t()) :: Workbench.Cmd.t()
  def publish(props, %State{} = state) do
    Cmd.async(
      fn ->
        state.client_module.publish(
          Map.fetch!(props.context, :api_base_url),
          state.room_id,
          state.publication_workspace || %{},
          state.publish_bindings,
          operator_module: Map.get(props.context, :operator_module),
          tenant_id: Map.get(props.context, :tenant_id, "workspace-local"),
          actor_id: Map.get(props.context, :actor_id, "operator-1")
        )
      end,
      &{:published, &1}
    )
  end
end
