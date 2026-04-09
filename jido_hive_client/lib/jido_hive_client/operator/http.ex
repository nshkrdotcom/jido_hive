defmodule JidoHiveClient.Operator.HTTP do
  @moduledoc false

  alias JidoHiveClient.Transport.HTTP, as: TransportHTTP

  @default_request_timeout_ms 15_000
  @default_connect_timeout_ms 5_000

  @spec get(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get(api_base_url, path, opts \\ []) do
    TransportHTTP.get(api_base_url, path, normalize_opts(opts))
  end

  @spec post(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def post(api_base_url, path, payload, opts \\ []) when is_map(payload) do
    TransportHTTP.post(api_base_url, path, payload, normalize_opts(opts))
  end

  defp normalize_opts(opts) do
    opts
    |> Keyword.put_new(:surface, :operator)
    |> Keyword.put_new(:lane, :operator_control)
    |> Keyword.put_new(:request_timeout_ms, @default_request_timeout_ms)
    |> Keyword.put_new(:connect_timeout_ms, @default_connect_timeout_ms)
  end
end
