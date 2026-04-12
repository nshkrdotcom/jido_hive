defmodule JidoHiveClient.Boundary.RoomApi.Http do
  @moduledoc false

  @behaviour JidoHiveClient.Boundary.RoomApi
  alias JidoHiveClient.Operator

  @request_timeout_ms 10_000
  @connect_timeout_ms 3_000

  @impl true
  def fetch_room(opts, room_id) do
    Operator.fetch_room(base_url(opts), room_id, operator_opts(opts, :room_hydrate))
  end

  @impl true
  def fetch_sync(opts, room_id, query_opts \\ []) do
    Operator.fetch_room_sync(
      base_url(opts),
      room_id,
      operator_opts(opts, :room_sync) ++ Keyword.take(query_opts, [:after, :operation_id])
    )
  end

  @impl true
  def fetch_timeline(opts, room_id, query_opts \\ []) do
    Operator.fetch_room_timeline(
      base_url(opts),
      room_id,
      operator_opts(opts, :room_sync) ++ Keyword.take(query_opts, [:after, :operation_id])
    )
  end

  @impl true
  def fetch_context_objects(opts, room_id) do
    with {:ok, room_snapshot} <- fetch_room(opts, room_id) do
      {:ok, Map.get(room_snapshot, "context_objects", [])}
    end
  end

  @impl true
  def submit_contribution(opts, room_id, payload) when is_map(payload) do
    Operator.submit_contribution(
      base_url(opts),
      room_id,
      payload,
      operator_opts(opts, :room_submit)
    )
  end

  defp base_url(opts),
    do: opts |> Keyword.get(:base_url, "http://127.0.0.1:4000/api") |> String.trim_trailing("/")

  defp operator_opts(opts, default_lane) do
    opts
    |> Keyword.take([:operation_id, :lane, :request_timeout_ms, :connect_timeout_ms])
    |> Keyword.put_new(:lane, default_lane)
    |> Keyword.put_new(:request_timeout_ms, @request_timeout_ms)
    |> Keyword.put_new(:connect_timeout_ms, @connect_timeout_ms)
  end
end
