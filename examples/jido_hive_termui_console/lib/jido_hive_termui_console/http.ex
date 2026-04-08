defmodule JidoHiveTermuiConsole.HTTP do
  @moduledoc false

  @spec get(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get(api_base_url, path), do: request(:get, api_base_url, path, nil)

  @spec post(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def post(api_base_url, path, payload) when is_map(payload) do
    request(:post, api_base_url, path, payload)
  end

  defp request(method, api_base_url, path, payload) do
    :ok = ensure_http_started()

    base_url =
      api_base_url
      |> to_string()
      |> String.trim_trailing("/")

    url = String.to_charlist(base_url <> path)
    headers = [{~c"content-type", ~c"application/json"}, {~c"accept", ~c"application/json"}]

    request =
      case method do
        :get -> {url, headers}
        :post -> {url, headers, ~c"application/json", Jason.encode!(payload)}
      end

    case :httpc.request(method, request, [], body_format: :binary) do
      {:ok, {{_version, status, _phrase}, _response_headers, body}} when status in 200..299 ->
        {:ok, decode_body(body)}

      {:ok, {{_version, 404, _phrase}, _response_headers, _body}} ->
        {:error, :not_found}

      {:ok, {{_version, status, _phrase}, _response_headers, body}} ->
        {:error, {:http_error, status, decode_body(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_http_started do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)
    :ok
  end

  defp decode_body(body) when body in ["", nil], do: %{}

  defp decode_body(body) do
    case Jason.decode(body) do
      {:ok, payload} -> payload
      {:error, _reason} -> %{"raw_body" => body}
    end
  end
end
