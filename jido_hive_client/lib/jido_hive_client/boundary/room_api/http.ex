defmodule JidoHiveClient.Boundary.RoomApi.Http do
  @moduledoc false

  @behaviour JidoHiveClient.Boundary.RoomApi
  alias JidoHiveClient.Transport.HTTP, as: TransportHTTP

  @request_timeout_ms 10_000
  @connect_timeout_ms 3_000

  @impl true
  def fetch_room(opts, room_id) do
    request(:get, opts, "/rooms/#{URI.encode_www_form(room_id)}", nil)
  end

  @impl true
  def fetch_timeline(opts, room_id, query_opts \\ []) do
    query =
      %{}
      |> maybe_put_query("after", Keyword.get(query_opts, :after))
      |> URI.encode_query()

    path =
      case query do
        "" -> "/rooms/#{URI.encode_www_form(room_id)}/timeline"
        encoded -> "/rooms/#{URI.encode_www_form(room_id)}/timeline?#{encoded}"
      end

    with {:ok, %{"data" => entries, "next_cursor" => next_cursor}} <-
           request(:get, opts, path, nil) do
      {:ok, %{entries: entries, next_cursor: next_cursor}}
    end
  end

  @impl true
  def fetch_context_objects(opts, room_id) do
    with {:ok, %{"data" => context_objects}} <-
           request(:get, opts, "/rooms/#{URI.encode_www_form(room_id)}/context_objects", nil) do
      {:ok, context_objects}
    end
  end

  @impl true
  def submit_contribution(opts, room_id, payload) when is_map(payload) do
    request(:post, opts, "/rooms/#{URI.encode_www_form(room_id)}/contributions", payload)
  end

  defp request(method, opts, path, payload) do
    base_url =
      opts
      |> Keyword.get(:base_url, "http://127.0.0.1:4000/api")
      |> String.trim_trailing("/")

    transport_opts =
      opts
      |> Keyword.take([:operation_id, :lane, :request_timeout_ms, :connect_timeout_ms])
      |> Keyword.put_new(:surface, :room_api)
      |> Keyword.put_new(:lane, default_lane(method, path))
      |> Keyword.put_new(:request_timeout_ms, @request_timeout_ms)
      |> Keyword.put_new(:connect_timeout_ms, @connect_timeout_ms)

    case method do
      :get ->
        TransportHTTP.get(base_url, path, transport_opts)

      :post ->
        TransportHTTP.post(base_url, path, payload, transport_opts)
    end
  end

  defp default_lane(:get, path) do
    if String.contains?(path, "/timeline") or String.contains?(path, "/context_objects") do
      :room_sync
    else
      :room_hydrate
    end
  end

  defp default_lane(:post, path) do
    if String.contains?(path, "/contributions"), do: :room_submit, else: :room_control
  end

  defp maybe_put_query(query, _key, nil), do: query
  defp maybe_put_query(query, key, value), do: Map.put(query, key, value)
end
