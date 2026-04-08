defmodule JidoHiveTermuiConsole do
  @moduledoc false

  alias JidoHiveTermuiConsole.{App, Config, Identity}
  alias TermUI.Runtime

  @default_api_base_url "http://127.0.0.1:4000/api"
  @default_poll_interval_ms 500

  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts \\ []) do
    :ok = Config.ensure_initialized()
    config = Config.load()
    identity = Identity.load(opts)
    route = Keyword.get(opts, :route, default_route(opts))

    runtime_opts =
      [
        root: App,
        route: route,
        api_base_url: option_or_config(opts, :api_base_url, config, @default_api_base_url),
        participant_id: identity.participant_id,
        participant_role: identity.participant_role,
        authority_level: identity.authority_level,
        poll_interval_ms:
          option_or_config(opts, :poll_interval_ms, config, @default_poll_interval_ms),
        embedded: Keyword.get(opts, :embedded),
        embedded_module: Keyword.get(opts, :embedded_module, JidoHiveClient.Embedded),
        event_log_poller_module:
          Keyword.get(opts, :event_log_poller_module, JidoHiveTermuiConsole.EventLogPoller),
        http_module: Keyword.get(opts, :http_module, JidoHiveTermuiConsole.HTTP),
        config_module: Keyword.get(opts, :config_module, JidoHiveTermuiConsole.Config),
        auth_module: Keyword.get(opts, :auth_module, JidoHiveTermuiConsole.Auth)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    runtime_module = Keyword.get(opts, :runtime_module, Runtime)
    runtime_module.run(runtime_opts)
  end

  defp default_route(opts) do
    case Keyword.get(opts, :room_id) do
      room_id when is_binary(room_id) and room_id != "" -> {:room, %{room_id: room_id}}
      _other -> {:lobby, %{}}
    end
  end

  defp option_or_config(opts, key, config, default) do
    Keyword.get(opts, key, Map.get(config, Atom.to_string(key), default))
  end
end
