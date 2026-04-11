defmodule JidoHiveSurface do
  @moduledoc """
  UI-neutral operator surface over `jido_hive_client`.
  """

  alias JidoHiveSurface.{Publications, Rooms}

  @spec list_rooms(String.t(), keyword()) :: [map()]
  def list_rooms(api_base_url, opts \\ []), do: Rooms.list(api_base_url, opts)

  @spec load_room_workspace(String.t(), String.t(), keyword()) :: map()
  def load_room_workspace(api_base_url, room_id, opts \\ []),
    do: Rooms.workspace(api_base_url, room_id, opts)

  @spec load_provenance(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, :not_found}
  def load_provenance(api_base_url, room_id, context_id, opts \\ []),
    do: Rooms.provenance(api_base_url, room_id, context_id, opts)

  @spec create_room(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_room(api_base_url, attrs, opts \\ []), do: Rooms.create(api_base_url, attrs, opts)

  @spec normalize_create_attrs(map()) :: {:ok, map()} | {:error, map()}
  def normalize_create_attrs(attrs), do: Rooms.normalize_create_attrs(attrs)

  @spec run_room(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_room(api_base_url, room_id, opts \\ []), do: Rooms.run(api_base_url, room_id, opts)

  @spec normalize_run_attrs(map()) :: {:ok, keyword()} | {:error, map()}
  def normalize_run_attrs(attrs), do: Rooms.normalize_run_attrs(attrs)

  @spec room_run_status(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def room_run_status(api_base_url, room_id, operation_id, opts \\ []),
    do: Rooms.run_status(api_base_url, room_id, operation_id, opts)

  @spec submit_steering(String.t(), String.t(), map(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def submit_steering(api_base_url, room_id, identity, text, opts \\ []),
    do: Rooms.submit_steering(api_base_url, room_id, identity, text, opts)

  @spec load_publication_workspace(String.t(), String.t(), String.t(), keyword()) :: map()
  def load_publication_workspace(api_base_url, room_id, subject, opts \\ []),
    do: Publications.workspace(api_base_url, room_id, subject, opts)

  @spec publish(String.t(), String.t(), map(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def publish(api_base_url, room_id, publication_workspace, bindings, opts \\ []),
    do: Publications.publish(api_base_url, room_id, publication_workspace, bindings, opts)
end
