defmodule JidoHiveWorkerRuntime.Control.Server do
  @moduledoc false

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    host = Keyword.get(opts, :host, "127.0.0.1")
    port = Keyword.fetch!(opts, :port)

    Plug.Cowboy.child_spec(
      scheme: :http,
      plug: {JidoHiveWorkerRuntime.Control.Router, opts},
      options: [ip: parse_host(host), port: port]
    )
  end

  defp parse_host(host) when is_binary(host) do
    host
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  end

  defp parse_host(host) when is_tuple(host), do: host
end
