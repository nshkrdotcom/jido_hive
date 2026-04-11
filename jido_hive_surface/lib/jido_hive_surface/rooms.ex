defmodule JidoHiveSurface.Rooms do
  @moduledoc """
  UI-neutral room workflows over `jido_hive_client`.
  """

  alias JidoHiveClient.{Operator, RoomCatalog, RoomSession, RoomWorkspace}

  @spec list(String.t(), keyword()) :: [RoomCatalog.room_summary()]
  def list(api_base_url, opts \\ []) when is_binary(api_base_url) and is_list(opts) do
    RoomCatalog.list(api_base_url, operator_module: operator_module(opts))
  end

  @spec normalize_create_attrs(map()) :: {:ok, map()} | {:error, map()}
  def normalize_create_attrs(attrs) when is_map(attrs) do
    brief =
      attrs
      |> value("brief")
      |> to_string()
      |> String.trim()

    room_id =
      attrs
      |> value("room_id")
      |> to_string()
      |> String.trim()
      |> case do
        "" -> generated_room_id()
        other -> other
      end

    if brief == "" do
      {:error, %{brief: "can't be blank"}}
    else
      {:ok,
       %{
         "room_id" => room_id,
         "brief" => brief,
         "participants" => value(attrs, "participants") || []
       }}
    end
  end

  def normalize_create_attrs(_attrs), do: {:error, %{brief: "can't be blank"}}

  @spec normalize_run_attrs(map()) :: {:ok, keyword()} | {:error, map()}
  def normalize_run_attrs(attrs) when is_map(attrs) do
    with {:ok, max_assignments} <- parse_optional_positive_integer(attrs, "max_assignments"),
         {:ok, assignment_timeout_ms} <-
           parse_optional_positive_integer(attrs, "assignment_timeout_ms") do
      {:ok,
       []
       |> maybe_put_option(:max_assignments, max_assignments)
       |> maybe_put_option(:assignment_timeout_ms, assignment_timeout_ms)}
    end
  end

  def normalize_run_attrs(_attrs), do: {:ok, []}

  @spec workspace(String.t(), String.t(), keyword()) :: RoomWorkspace.t()
  def workspace(api_base_url, room_id, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_list(opts) do
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

  @spec provenance(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, :not_found}
  def provenance(api_base_url, room_id, context_id, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_binary(context_id) and
             is_list(opts) do
    operator_module = operator_module(opts)
    sync_opts = if(after_cursor = Keyword.get(opts, :after), do: [after: after_cursor], else: [])

    {:ok, sync_result} = operator_module.fetch_room_sync(api_base_url, room_id, sync_opts)
    snapshot = hydrate_sync_snapshot(sync_result)

    RoomWorkspace.provenance(snapshot, context_id)
  end

  @spec create(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def create(api_base_url, attrs, opts \\ [])
      when is_binary(api_base_url) and is_map(attrs) and is_list(opts) do
    operator_module = operator_module(opts)
    save_room? = Keyword.get(opts, :save_room?, true)

    with {:ok, room} <- operator_module.create_room(api_base_url, attrs),
         :ok <- maybe_save_room(operator_module, api_base_url, attrs, room, save_room?) do
      {:ok, room}
    end
  end

  @spec run(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(api_base_url, room_id, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_list(opts) do
    operator_module = operator_module(opts)

    run_opts =
      []
      |> maybe_put_option(:max_assignments, Keyword.get(opts, :max_assignments))
      |> maybe_put_option(:assignment_timeout_ms, Keyword.get(opts, :assignment_timeout_ms))
      |> maybe_put_option(:operation_id, Keyword.get(opts, :operation_id))
      |> maybe_put_option(:request_timeout_ms, Keyword.get(opts, :request_timeout_ms))
      |> maybe_put_option(:connect_timeout_ms, Keyword.get(opts, :connect_timeout_ms))

    operator_module.start_room_run_operation(api_base_url, room_id, run_opts)
  end

  @spec run_status(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def run_status(api_base_url, room_id, operation_id, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_binary(operation_id) and
             is_list(opts) do
    operator_module = operator_module(opts)

    status_opts =
      []
      |> maybe_put_option(:operation_id, Keyword.get(opts, :request_operation_id))
      |> maybe_put_option(:request_timeout_ms, Keyword.get(opts, :request_timeout_ms))
      |> maybe_put_option(:connect_timeout_ms, Keyword.get(opts, :connect_timeout_ms))

    operator_module.fetch_room_run_operation(api_base_url, room_id, operation_id, status_opts)
  end

  @spec submit_steering(String.t(), String.t(), map(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def submit_steering(api_base_url, room_id, identity, text, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_map(identity) and is_binary(text) and
             is_list(opts) do
    room_session_module =
      Keyword.get(opts, :room_session_module) ||
        Keyword.get(opts, :room_session_module_fallback) ||
        RoomSession

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

  defp operator_module(opts) do
    Keyword.get(opts, :operator_module) ||
      Keyword.get(opts, :operator_module_fallback) ||
      Operator
  end

  defp hydrate_sync_snapshot(sync_result) do
    sync_result.room_snapshot
    |> Map.put("timeline", sync_result.entries)
    |> Map.put("context_objects", sync_result.context_objects)
    |> Map.put("operations", sync_result.operations)
    |> Map.put("next_cursor", sync_result.next_cursor)
  end

  defp maybe_save_room(_operator_module, _api_base_url, _attrs, _room, false), do: :ok

  defp maybe_save_room(operator_module, api_base_url, attrs, room, true) do
    case room_id_from(attrs, room) do
      nil -> :ok
      room_id -> operator_module.add_saved_room(room_id, api_base_url)
    end
  end

  defp room_id_from(attrs, room) do
    Map.get(attrs, "room_id") || Map.get(attrs, :room_id) || Map.get(room, "room_id") ||
      Map.get(room, :room_id)
  end

  defp parse_optional_positive_integer(attrs, key) do
    case value(attrs, key) do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed > 0 -> {:ok, parsed}
          _other -> {:error, %{String.to_existing_atom(key) => "must be a positive integer"}}
        end

      _other ->
        {:error, %{String.to_existing_atom(key) => "must be a positive integer"}}
    end
  rescue
    ArgumentError ->
      {:error, %{invalid: "unexpected field"}}
  end

  defp generated_room_id do
    "room-#{System.unique_integer([:positive])}"
  end

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp maybe_put_option(opts, _key, nil), do: opts
  defp maybe_put_option(opts, key, value), do: Keyword.put(opts, key, value)
end
