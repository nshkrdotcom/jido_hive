defmodule JidoHiveSurface.Publications do
  @moduledoc """
  UI-neutral publication workflows over `jido_hive_client`.
  """

  alias JidoHiveClient.{Operator, PublicationWorkspace}

  @spec workspace(String.t(), String.t(), String.t(), keyword()) :: PublicationWorkspace.t()
  def workspace(api_base_url, room_id, subject, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_binary(subject) and
             is_list(opts) do
    operator_module = operator_module(opts)
    {:ok, publication_plan} = operator_module.fetch_publication_plan(api_base_url, room_id)
    auth_state = operator_module.load_auth_state(api_base_url, subject)

    PublicationWorkspace.build(publication_plan, auth_state,
      selected_channel: Keyword.get(opts, :selected_channel)
    )
  end

  @spec publish(String.t(), String.t(), PublicationWorkspace.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def publish(api_base_url, room_id, publication_workspace, bindings, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_map(publication_workspace) and
             is_map(bindings) and is_list(opts) do
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

  defp operator_module(opts) do
    Keyword.get(opts, :operator_module) ||
      Keyword.get(opts, :operator_module_fallback) ||
      Operator
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
