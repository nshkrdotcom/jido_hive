defmodule JidoHive.Switchyard.Site.Client do
  @moduledoc """
  Thin site-side client helpers over `jido_hive_client`.
  """

  alias JidoHiveClient.{Operator, PublicationWorkspace, RoomCatalog, RoomSession, RoomWorkspace}

  @spec list_rooms(String.t(), keyword()) :: [RoomCatalog.room_summary()]
  def list_rooms(api_base_url, opts \\ []) when is_binary(api_base_url) do
    RoomCatalog.list(api_base_url, operator_module: operator_module(opts))
  end

  @spec load_room_workspace(String.t(), String.t(), keyword()) :: RoomWorkspace.t()
  def load_room_workspace(api_base_url, room_id, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) do
    operator_module = operator_module(opts)
    after_cursor = Keyword.get(opts, :after)
    sync_opts = if(after_cursor, do: [after: after_cursor], else: [])

    {:ok, sync_result} = operator_module.fetch_room_sync(api_base_url, room_id, sync_opts)
    snapshot = hydrate_sync_snapshot(sync_result)

    RoomWorkspace.build(snapshot,
      selected_context_id: Keyword.get(opts, :selected_context_id),
      participant_id: Keyword.get(opts, :participant_id),
      pending_submit: Keyword.get(opts, :pending_submit)
    )
  end

  @spec load_publication_workspace(String.t(), String.t(), String.t(), keyword()) ::
          PublicationWorkspace.t()
  def load_publication_workspace(api_base_url, room_id, subject, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_binary(subject) do
    operator_module = operator_module(opts)
    {:ok, publication_plan} = operator_module.fetch_publication_plan(api_base_url, room_id)
    auth_state = operator_module.load_auth_state(api_base_url, subject)

    PublicationWorkspace.build(publication_plan, auth_state,
      selected_channel: Keyword.get(opts, :selected_channel)
    )
  end

  @spec load_provenance(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, :not_found}
  def load_provenance(api_base_url, room_id, context_id, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_binary(context_id) do
    operator_module = operator_module(opts)
    sync_opts = if(after_cursor = Keyword.get(opts, :after), do: [after: after_cursor], else: [])

    {:ok, sync_result} = operator_module.fetch_room_sync(api_base_url, room_id, sync_opts)
    snapshot = hydrate_sync_snapshot(sync_result)

    RoomWorkspace.provenance(snapshot, context_id)
  end

  @spec submit_steering(String.t(), String.t(), map(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def submit_steering(api_base_url, room_id, identity, text, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_map(identity) and is_binary(text) do
    room_session_module = Keyword.get(opts, :room_session_module) || RoomSession

    with {:ok, session} <-
           room_session_module.start_link(
             api_base_url: api_base_url,
             room_id: room_id,
             participant_id: Map.fetch!(identity, :participant_id),
             participant_role: Map.fetch!(identity, :participant_role),
             authority_level: Map.fetch!(identity, :authority_level)
           ),
         {:ok, result} <- room_session_module.submit_chat(session, %{text: text}) do
      :ok = room_session_module.shutdown(session)
      {:ok, result}
    end
  end

  @spec publish(String.t(), String.t(), PublicationWorkspace.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def publish(api_base_url, room_id, publication_workspace, bindings, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_map(publication_workspace) and
             is_map(bindings) do
    operator_module = operator_module(opts)
    selected_channels = selected_channels(publication_workspace)

    payload = %{
      "channels" => selected_channels,
      "bindings" => bindings,
      "tenant_id" => Keyword.get(opts, :tenant_id, "workspace-local"),
      "actor_id" => Keyword.get(opts, :actor_id, "operator-1"),
      "connections" =>
        Map.new(selected_channels, fn channel ->
          {channel, connection_id(publication_workspace, channel)}
        end)
    }

    operator_module.publish_room(api_base_url, room_id, payload)
  end

  defp operator_module(opts), do: Keyword.get(opts, :operator_module) || Operator

  defp hydrate_sync_snapshot(sync_result) do
    sync_result.room_snapshot
    |> Map.put("timeline", sync_result.entries)
    |> Map.put("context_objects", sync_result.context_objects)
    |> Map.put("operations", sync_result.operations)
    |> Map.put("next_cursor", sync_result.next_cursor)
  end

  defp selected_channels(publication_workspace) do
    publication_workspace
    |> Map.get(:channels, [])
    |> Enum.filter(&Map.get(&1, :selected?, false))
    |> Enum.map(&Map.get(&1, :channel))
  end

  defp connection_id(publication_workspace, channel) do
    publication_workspace
    |> Map.get(:channels, [])
    |> Enum.find(&(Map.get(&1, :channel) == channel))
    |> case do
      nil -> nil
      selected_channel -> get_in(selected_channel, [:auth, :connection_id])
    end
  end
end
