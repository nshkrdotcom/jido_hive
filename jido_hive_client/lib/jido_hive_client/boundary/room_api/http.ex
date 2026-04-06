defmodule JidoHiveClient.Boundary.RoomApi.Http do
  @moduledoc false

  @behaviour JidoHiveClient.Boundary.RoomApi

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
    :ok = ensure_http_started()

    base_url =
      opts
      |> Keyword.get(:base_url, "http://127.0.0.1:4000/api")
      |> String.trim_trailing("/")

    url = String.to_charlist(base_url <> path)

    headers = [{~c"content-type", ~c"application/json"}, {~c"accept", ~c"application/json"}]

    request =
      case method do
        :get -> {url, headers}
        :post -> {url, headers, ~c"application/json", Jason.encode!(payload)}
      end

    case :httpc.request(method, request, [], body_format: :binary) do
      {:ok, {{_version, status, _reason_phrase}, _response_headers, body}}
      when status in 200..299 ->
        {:ok, decode_body(body)}

      {:ok, {{_version, 404, _reason_phrase}, _response_headers, _body}} ->
        {:error, :room_not_found}

      {:ok, {{_version, status, _reason_phrase}, _response_headers, body}} ->
        {:error, {:http_error, status, decode_body(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put_query(query, _key, nil), do: query
  defp maybe_put_query(query, key, value), do: Map.put(query, key, value)

  defp decode_body(body) when body in ["", nil], do: %{}

  defp decode_body(body) do
    case Jason.decode(body) do
      {:ok, payload} -> payload
      {:error, _reason} -> %{"raw_body" => body}
    end
  end

  defp ensure_http_started do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)
    :ok
  end
end
