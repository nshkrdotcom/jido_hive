defmodule JidoHiveClient.Transport.HTTP do
  @moduledoc false

  require Logger

  alias JidoHiveClient.DebugTrace

  @default_request_timeout_ms 15_000
  @default_connect_timeout_ms 5_000
  @response_options [body_format: :binary]
  @stats_table :jido_hive_client_transport_http_stats

  @spec get(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get(api_base_url, path, opts \\ []), do: request(:get, api_base_url, path, nil, opts)

  @spec post(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def post(api_base_url, path, payload, opts \\ []) when is_map(payload) do
    request(:post, api_base_url, path, payload, opts)
  end

  @spec request(:get | :post, String.t(), String.t(), map() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def request(method, api_base_url, path, payload, opts)
      when method in [:get, :post] and is_binary(path) and is_list(opts) do
    :ok = ensure_http_started()

    base_url =
      api_base_url
      |> to_string()
      |> String.trim()
      |> String.trim_trailing("/")

    url = String.to_charlist(base_url <> path)
    headers = [{~c"content-type", ~c"application/json"}, {~c"accept", ~c"application/json"}]
    lane = Keyword.get(opts, :lane, :default)
    surface = Keyword.get(opts, :surface, :unknown)
    request_timeout_ms = Keyword.get(opts, :request_timeout_ms, @default_request_timeout_ms)
    connect_timeout_ms = Keyword.get(opts, :connect_timeout_ms, @default_connect_timeout_ms)
    operation_id = Keyword.get(opts, :operation_id)
    request_options = [timeout: request_timeout_ms, connect_timeout: connect_timeout_ms]
    started_at = System.monotonic_time(:millisecond)
    queued_at = now_iso8601()
    profile = lane_profile(lane)

    request_meta = %{
      lane: lane,
      surface: surface,
      operation_id: operation_id,
      method: method,
      path: path,
      started_at: started_at,
      request_timeout_ms: request_timeout_ms,
      connect_timeout_ms: connect_timeout_ms
    }

    request =
      case method do
        :get -> {url, headers}
        :post -> {url, headers, ~c"application/json", Jason.encode!(payload)}
      end

    record_request_start(request_meta, queued_at)

    request_result =
      case ensure_http_profile_started(profile) do
        :ok -> request_with_retry(method, request, request_options, @response_options, profile)
        {:error, reason} -> {:error, {:http_profile_not_started, profile, reason}}
      end

    handle_response(request_result, request_meta)
  end

  @spec diagnostics() :: map()
  def diagnostics do
    ensure_stats_table()

    lanes =
      @stats_table
      |> :ets.tab2list()
      |> Enum.map(fn {_lane, stats} -> stats end)
      |> Enum.sort_by(&Map.get(&1, "lane"))

    %{
      "lanes" => lanes,
      "ts" => now_iso8601()
    }
  end

  defp ensure_http_started do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)
    :ok
  end

  defp ensure_http_profile_started(profile) do
    case :httpc.info(profile) do
      {:error, {:not_started, ^profile}} ->
        case :httpc.start_service([{:profile, profile}]) do
          {:ok, _pid} ->
            :ok

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "transport http profile failed to start profile=#{profile} reason=#{inspect(reason)}"
            )

            {:error, reason}
        end

      _ ->
        :ok
    end
  end

  defp request_with_retry(method, request, request_options, response_options, profile) do
    response = request_once(method, request, request_options, response_options, profile)

    case response do
      {:error, {:http_profile_not_started, ^profile}} ->
        case ensure_http_profile_started(profile) do
          :ok ->
            request_once(method, request, request_options, response_options, profile)

          {:error, reason} ->
            {:error, {:http_profile_not_started, profile, reason}}
        end

      _ ->
        response
    end
  end

  defp request_once(method, request, request_options, response_options, profile) do
    :httpc.request(method, request, request_options, response_options, profile)
  catch
    :exit, {:noproc, _} ->
      {:error, {:http_profile_not_started, profile}}

    :exit, reason ->
      {:error, {:http_exit, reason}}
  end

  defp ensure_stats_table do
    case :ets.whereis(@stats_table) do
      :undefined ->
        try do
          :ets.new(@stats_table, [
            :named_table,
            :public,
            :set,
            read_concurrency: true,
            write_concurrency: true
          ])
        rescue
          ArgumentError -> :ok
        end

      _table ->
        :ok
    end

    :ok
  end

  defp default_lane_stats(lane, profile) do
    %{
      "lane" => Atom.to_string(lane),
      "profile" => Atom.to_string(profile),
      "active_requests" => 0,
      "total_requests" => 0,
      "completed_requests" => 0,
      "failed_requests" => 0,
      "timeout_count" => 0,
      "queue_depth" => 0,
      "oldest_waiting_ms" => nil,
      "last_started_at" => nil,
      "last_completed_at" => nil,
      "last_request" => nil,
      "last_failure" => nil
    }
  end

  defp lane_profile(lane), do: :"jido_hive_transport_#{lane}"

  defp update_lane_stats(lane, fun) do
    ensure_stats_table()
    profile = lane_profile(lane)

    current =
      case :ets.lookup(@stats_table, lane) do
        [{^lane, stats}] -> stats
        [] -> default_lane_stats(lane, profile)
      end

    next = fun.(current)
    true = :ets.insert(@stats_table, {lane, next})
    next
  end

  defp record_request_start(request_meta, queued_at) do
    started_at = now_iso8601()

    update_lane_stats(request_meta.lane, fn stats ->
      stats
      |> Map.update!("active_requests", &(&1 + 1))
      |> Map.update!("total_requests", &(&1 + 1))
      |> Map.put("last_started_at", started_at)
      |> Map.put("last_request", %{
        "surface" => Atom.to_string(request_meta.surface),
        "operation_id" => request_meta.operation_id,
        "method" => request_method(request_meta),
        "path" => request_meta.path,
        "request_timeout_ms" => request_meta.request_timeout_ms,
        "connect_timeout_ms" => request_meta.connect_timeout_ms,
        "queued_at" => queued_at,
        "started_at" => started_at
      })
    end)

    Logger.debug(
      "transport http request started surface=#{request_meta.surface} lane=#{request_meta.lane} operation_id=#{request_meta.operation_id || "none"} method=#{request_method(request_meta)} path=#{request_meta.path} timeout_ms=#{request_meta.request_timeout_ms} connect_timeout_ms=#{request_meta.connect_timeout_ms}"
    )

    DebugTrace.emit(:debug, "transport.http.request.started", %{
      surface: request_meta.surface,
      lane: request_meta.lane,
      operation_id: request_meta.operation_id,
      method: request_method(request_meta),
      path: request_meta.path,
      request_timeout_ms: request_meta.request_timeout_ms,
      connect_timeout_ms: request_meta.connect_timeout_ms
    })
  end

  defp handle_response({:ok, {{_version, status, _phrase}, _headers, body}}, request_meta)
       when status in 200..299 do
    log_complete(request_meta, status)
    {:ok, decode_body(body)}
  end

  defp handle_response({:ok, {{_version, 404, _phrase}, _headers, _body}}, request_meta) do
    log_complete(request_meta, 404)
    {:error, :not_found}
  end

  defp handle_response({:ok, {{_version, status, _phrase}, _headers, body}}, request_meta) do
    log_complete(request_meta, status)
    {:error, {:http_error, status, decode_body(body)}}
  end

  defp handle_response({:error, :timeout}, request_meta) do
    elapsed_ms = elapsed_ms(request_meta.started_at)

    log_failure(request_meta, ":timeout", elapsed_ms, timeout?: true)

    {:error, {:timeout, timeout_metadata(request_meta, elapsed_ms)}}
  end

  defp handle_response({:error, reason}, request_meta) do
    elapsed_ms = elapsed_ms(request_meta.started_at)

    log_failure(request_meta, inspect(reason), elapsed_ms)

    {:error, reason}
  end

  defp log_complete(request_meta, status) do
    elapsed_ms = elapsed_ms(request_meta.started_at)
    completed_at = now_iso8601()

    update_lane_stats(request_meta.lane, fn stats ->
      stats
      |> Map.update!("active_requests", &max(&1 - 1, 0))
      |> Map.update!("completed_requests", &(&1 + 1))
      |> Map.put("last_completed_at", completed_at)
      |> Map.put("last_request", %{
        "surface" => Atom.to_string(request_meta.surface),
        "operation_id" => request_meta.operation_id,
        "method" => request_method(request_meta),
        "path" => request_meta.path,
        "status" => status,
        "elapsed_ms" => elapsed_ms,
        "completed_at" => completed_at
      })
    end)

    Logger.debug(
      "transport http request completed surface=#{request_meta.surface} lane=#{request_meta.lane} operation_id=#{request_meta.operation_id || "none"} method=#{request_method(request_meta)} path=#{request_meta.path} status=#{status} elapsed_ms=#{elapsed_ms}"
    )

    DebugTrace.emit(:debug, "transport.http.request.completed", %{
      surface: request_meta.surface,
      lane: request_meta.lane,
      operation_id: request_meta.operation_id,
      method: request_method(request_meta),
      path: request_meta.path,
      status: status,
      elapsed_ms: elapsed_ms
    })
  end

  defp log_failure(request_meta, reason, elapsed_ms, opts \\ []) do
    completed_at = now_iso8601()
    timeout? = Keyword.get(opts, :timeout?, false)

    update_lane_stats(request_meta.lane, fn stats ->
      stats
      |> Map.update!("active_requests", &max(&1 - 1, 0))
      |> Map.update!("failed_requests", &(&1 + 1))
      |> maybe_increment_timeout(timeout?)
      |> Map.put("last_completed_at", completed_at)
      |> Map.put("last_failure", %{
        "surface" => Atom.to_string(request_meta.surface),
        "operation_id" => request_meta.operation_id,
        "method" => request_method(request_meta),
        "path" => request_meta.path,
        "reason" => reason,
        "elapsed_ms" => elapsed_ms,
        "request_timeout_ms" => request_meta.request_timeout_ms,
        "connect_timeout_ms" => request_meta.connect_timeout_ms,
        "completed_at" => completed_at
      })
    end)

    Logger.error(
      "transport http request failed surface=#{request_meta.surface} lane=#{request_meta.lane} operation_id=#{request_meta.operation_id || "none"} method=#{request_method(request_meta)} path=#{request_meta.path} reason=#{reason} elapsed_ms=#{elapsed_ms} timeout_ms=#{request_meta.request_timeout_ms}"
    )

    DebugTrace.emit(:error, "transport.http.request.failed", %{
      surface: request_meta.surface,
      lane: request_meta.lane,
      operation_id: request_meta.operation_id,
      method: request_method(request_meta),
      path: request_meta.path,
      reason: reason,
      elapsed_ms: elapsed_ms,
      request_timeout_ms: request_meta.request_timeout_ms,
      connect_timeout_ms: request_meta.connect_timeout_ms
    })
  end

  defp maybe_increment_timeout(stats, true), do: Map.update!(stats, "timeout_count", &(&1 + 1))
  defp maybe_increment_timeout(stats, false), do: stats

  defp timeout_metadata(request_meta, elapsed_ms) do
    %{
      method: request_method(request_meta),
      path: request_meta.path,
      lane: Atom.to_string(request_meta.lane),
      surface: Atom.to_string(request_meta.surface),
      elapsed_ms: elapsed_ms,
      request_timeout_ms: request_meta.request_timeout_ms,
      connect_timeout_ms: request_meta.connect_timeout_ms,
      operation_id: request_meta.operation_id
    }
  end

  defp request_method(request_meta), do: String.upcase(to_string(request_meta.method))

  defp decode_body(body) when body in ["", nil], do: %{}

  defp decode_body(body) do
    case Jason.decode(body) do
      {:ok, payload} -> payload
      {:error, _reason} -> %{"raw_body" => body}
    end
  end

  defp elapsed_ms(started_at) do
    System.monotonic_time(:millisecond) - started_at
  end

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end
end
