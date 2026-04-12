defmodule JidoHivePublications do
  @moduledoc """
  Explicit publication extension over canonical Jido Hive room resources.
  """

  alias JidoHiveClient.Operator
  alias JidoHivePublications.{PublicationWorkspace, Service, Storage}

  @spec plan_publication(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def plan_publication(api_base_url, room_id)
      when is_binary(api_base_url) and is_binary(room_id) do
    with {:ok, snapshot} <- Operator.fetch_room(api_base_url, room_id) do
      {:ok, Service.build_plan(snapshot)}
    end
  end

  @spec start_publication_run({String.t(), String.t()} | map(), map()) ::
          {:ok, map()} | {:error, term()}
  def start_publication_run({api_base_url, room_id}, attrs)
      when is_binary(api_base_url) and is_binary(room_id) and is_map(attrs) do
    with {:ok, snapshot} <- Operator.fetch_room(api_base_url, room_id) do
      Service.execute(snapshot, attrs)
    end
  end

  def start_publication_run(%{} = snapshot, attrs) when is_map(attrs) do
    Service.execute(snapshot, attrs)
  end

  @spec fetch_publication_run(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_publication_run(room_id, publication_run_id)
      when is_binary(room_id) and is_binary(publication_run_id) do
    Storage.fetch_run(room_id, publication_run_id)
  end

  @spec list_publication_runs(String.t(), keyword()) :: {:ok, [map()]}
  def list_publication_runs(room_id, _opts \\ []) when is_binary(room_id) do
    {:ok, Storage.list_runs(room_id)}
  end

  @spec load_publication_workspace(String.t(), String.t(), String.t(), keyword()) :: map()
  def load_publication_workspace(api_base_url, room_id, subject, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_binary(subject) and
             is_list(opts) do
    operator_module = operator_module(opts)
    {:ok, snapshot} = operator_module.fetch_room(api_base_url, room_id)
    auth_state = operator_module.load_auth_state(api_base_url, subject)

    PublicationWorkspace.build(Service.build_plan(snapshot), auth_state,
      selected_channel: Keyword.get(opts, :selected_channel)
    )
  end

  @spec workspace(String.t(), String.t(), String.t(), keyword()) :: map()
  def workspace(api_base_url, room_id, subject, opts \\ []) do
    load_publication_workspace(api_base_url, room_id, subject, opts)
  end

  @spec publish(String.t(), String.t(), map(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def publish(api_base_url, room_id, publication_workspace, bindings, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_map(publication_workspace) and
             is_map(bindings) and is_list(opts) do
    selected_channels = selected_channels(publication_workspace)
    operator_module = operator_module(opts)

    attrs = %{
      "channels" => selected_channels,
      "bindings" => bindings,
      "tenant_id" => Keyword.get(opts, :tenant_id, "workspace-local"),
      "actor_id" => Keyword.get(opts, :actor_id, "operator-1"),
      "connections" =>
        Map.new(selected_channels, fn channel ->
          {channel, connection_id(publication_workspace, channel)}
        end)
    }

    with {:ok, snapshot} <- operator_module.fetch_room(api_base_url, room_id) do
      Service.execute(snapshot, attrs)
    end
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
