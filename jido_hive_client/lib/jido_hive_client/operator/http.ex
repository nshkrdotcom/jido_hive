defmodule JidoHiveClient.Operator.HTTP do
  @moduledoc false

  require Logger

  alias JidoHiveClient.DebugTrace

  @default_request_timeout_ms 15_000
  @default_connect_timeout_ms 5_000
  @response_options [body_format: :binary]

  @spec get(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get(api_base_url, path, opts \\ []), do: request(:get, api_base_url, path, nil, opts)

  @spec post(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def post(api_base_url, path, payload, opts \\ []) when is_map(payload) do
    request(:post, api_base_url, path, payload, opts)
  end

  defp request(method, api_base_url, path, payload, opts) do
    :ok = ensure_http_started()

    base_url =
      api_base_url
      |> to_string()
      |> String.trim()
      |> String.trim_trailing("/")

    url = String.to_charlist(base_url <> path)
    headers = [{~c"content-type", ~c"application/json"}, {~c"accept", ~c"application/json"}]
    request_timeout_ms = Keyword.get(opts, :request_timeout_ms, @default_request_timeout_ms)
    connect_timeout_ms = Keyword.get(opts, :connect_timeout_ms, @default_connect_timeout_ms)
    operation_id = Keyword.get(opts, :operation_id)
    request_options = [timeout: request_timeout_ms, connect_timeout: connect_timeout_ms]
    started_at = System.monotonic_time(:millisecond)

    request =
      case method do
        :get -> {url, headers}
        :post -> {url, headers, ~c"application/json", Jason.encode!(payload)}
      end

    Logger.debug(
      "operator http request started operation_id=#{operation_id || "none"} method=#{String.upcase(to_string(method))} path=#{path} timeout_ms=#{request_timeout_ms} connect_timeout_ms=#{connect_timeout_ms}"
    )

    DebugTrace.emit(:debug, "operator.http.request.started", %{
      operation_id: operation_id,
      method: String.upcase(to_string(method)),
      path: path,
      request_timeout_ms: request_timeout_ms,
      connect_timeout_ms: connect_timeout_ms
    })

    :httpc.request(method, request, request_options, @response_options)
    |> handle_response(
      method,
      path,
      operation_id,
      started_at,
      request_timeout_ms,
      connect_timeout_ms
    )
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

  defp handle_response(
         {:ok, {{_version, status, _phrase}, _response_headers, body}},
         method,
         path,
         operation_id,
         started_at,
         _request_timeout_ms,
         _connect_timeout_ms
       )
       when status in 200..299 do
    log_complete(method, path, operation_id, status, started_at)
    {:ok, decode_body(body)}
  end

  defp handle_response(
         {:ok, {{_version, 404, _phrase}, _response_headers, _body}},
         method,
         path,
         operation_id,
         started_at,
         _request_timeout_ms,
         _connect_timeout_ms
       ) do
    log_complete(method, path, operation_id, 404, started_at)
    {:error, :not_found}
  end

  defp handle_response(
         {:ok, {{_version, status, _phrase}, _response_headers, body}},
         method,
         path,
         operation_id,
         started_at,
         _request_timeout_ms,
         _connect_timeout_ms
       ) do
    log_complete(method, path, operation_id, status, started_at)
    {:error, {:http_error, status, decode_body(body)}}
  end

  defp handle_response(
         {:error, :timeout},
         method,
         path,
         operation_id,
         started_at,
         request_timeout_ms,
         connect_timeout_ms
       ) do
    elapsed_ms = elapsed_ms(started_at)

    Logger.error(
      "operator http request failed operation_id=#{operation_id || "none"} method=#{String.upcase(to_string(method))} path=#{path} reason=:timeout elapsed_ms=#{elapsed_ms} timeout_ms=#{request_timeout_ms}"
    )

    DebugTrace.emit(:error, "operator.http.request.failed", %{
      operation_id: operation_id,
      method: String.upcase(to_string(method)),
      path: path,
      reason: ":timeout",
      elapsed_ms: elapsed_ms,
      request_timeout_ms: request_timeout_ms,
      connect_timeout_ms: connect_timeout_ms
    })

    {:error,
     {:timeout,
      %{
        method: String.upcase(to_string(method)),
        path: path,
        elapsed_ms: elapsed_ms,
        request_timeout_ms: request_timeout_ms,
        connect_timeout_ms: connect_timeout_ms,
        operation_id: operation_id
      }}}
  end

  defp handle_response(
         {:error, reason},
         method,
         path,
         operation_id,
         started_at,
         request_timeout_ms,
         connect_timeout_ms
       ) do
    elapsed_ms = elapsed_ms(started_at)

    Logger.error(
      "operator http request failed operation_id=#{operation_id || "none"} method=#{String.upcase(to_string(method))} path=#{path} reason=#{inspect(reason)} elapsed_ms=#{elapsed_ms} timeout_ms=#{request_timeout_ms}"
    )

    DebugTrace.emit(:error, "operator.http.request.failed", %{
      operation_id: operation_id,
      method: String.upcase(to_string(method)),
      path: path,
      reason: inspect(reason),
      elapsed_ms: elapsed_ms,
      request_timeout_ms: request_timeout_ms,
      connect_timeout_ms: connect_timeout_ms
    })

    {:error, reason}
  end

  defp log_complete(method, path, operation_id, status, started_at) do
    elapsed_ms = elapsed_ms(started_at)

    Logger.debug(
      "operator http request completed operation_id=#{operation_id || "none"} method=#{String.upcase(to_string(method))} path=#{path} status=#{status} elapsed_ms=#{elapsed_ms}"
    )

    DebugTrace.emit(:debug, "operator.http.request.completed", %{
      operation_id: operation_id,
      method: String.upcase(to_string(method)),
      path: path,
      status: status,
      elapsed_ms: elapsed_ms
    })
  end

  defp elapsed_ms(started_at) do
    System.monotonic_time(:millisecond) - started_at
  end
end
