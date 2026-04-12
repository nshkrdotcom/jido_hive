defmodule JidoHiveWorkerRuntime.Boundary.ServerAPI.HTTP do
  @moduledoc false

  @behaviour JidoHiveWorkerRuntime.Boundary.ServerAPI

  @http_timeout 5_000
  @request_headers [{~c"content-type", ~c"application/json"}]

  @impl true
  def list_rooms(api_base_url, participant_id)
      when is_binary(api_base_url) and is_binary(participant_id) do
    path = "#{api_base_url}/rooms?participant_id=#{URI.encode_www_form(participant_id)}"

    with {:ok, %{"data" => rooms}} when is_list(rooms) <- request(:get, path) do
      {:ok, rooms}
    end
  end

  @impl true
  def list_room_events(api_base_url, room_id, after_sequence)
      when is_binary(api_base_url) and is_binary(room_id) and is_integer(after_sequence) do
    path =
      "#{api_base_url}/rooms/#{URI.encode_www_form(room_id)}/events?after=#{after_sequence}"

    with {:ok, %{"data" => events}} when is_list(events) <- request(:get, path) do
      {:ok, events}
    end
  end

  @impl true
  def upsert_target(api_base_url, attrs) when is_binary(api_base_url) and is_map(attrs) do
    with {:ok, %{"data" => target}} when is_map(target) <-
           request(:post, "#{api_base_url}/targets", %{"data" => attrs}) do
      {:ok, target}
    end
  end

  @impl true
  def mark_target_offline(api_base_url, target_id)
      when is_binary(api_base_url) and is_binary(target_id) do
    case request(:delete, "#{api_base_url}/targets/#{URI.encode_www_form(target_id)}") do
      {:ok, _payload} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(method, url, payload \\ nil)

  defp request(:get, url, _payload) do
    case :httpc.request(:get, {to_charlist(url), []}, http_opts(), body_opts()) do
      {:ok, {{_, status, _}, _headers, body}} when status in 200..299 ->
        decode_body(body)

      {:ok, {{_, status, _}, _headers, body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(:delete, url, _payload) do
    case :httpc.request(:delete, {to_charlist(url), []}, http_opts(), body_opts()) do
      {:ok, {{_, status, _}, _headers, body}} when status in 200..299 ->
        decode_body(body)

      {:ok, {{_, status, _}, _headers, body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(:post, url, payload) when is_map(payload) do
    encoded = Jason.encode!(payload)

    case :httpc.request(
           :post,
           {to_charlist(url), @request_headers, ~c"application/json", encoded},
           http_opts(),
           body_opts()
         ) do
      {:ok, {{_, status, _}, _headers, body}} when status in 200..299 ->
        decode_body(body)

      {:ok, {{_, status, _}, _headers, body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_body(body) when is_list(body), do: decode_body(IO.iodata_to_binary(body))
  defp decode_body(""), do: {:ok, %{}}

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp http_opts do
    [
      timeout: @http_timeout,
      connect_timeout: @http_timeout
    ]
  end

  defp body_opts do
    [body_format: :binary]
  end
end
