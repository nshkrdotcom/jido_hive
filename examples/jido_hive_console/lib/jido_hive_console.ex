defmodule JidoHiveConsole do
  @moduledoc false

  alias JidoHiveClient.Operator
  alias JidoHiveClient.Polling
  alias JidoHiveConsole.{App, Identity}

  @default_api_base_url "http://127.0.0.1:4000/api"
  @default_poll_interval_ms Polling.default_interval_ms()

  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts \\ []) do
    operator_module = Keyword.get(opts, :operator_module, Operator)
    :ok = operator_module.ensure_initialized()
    config = operator_module.load_config()
    identity = Identity.load(Keyword.put(opts, :operator_module, operator_module))
    route = Keyword.get(opts, :route, default_route(opts))

    poll_interval_ms =
      opts
      |> option_or_config(:poll_interval_ms, config, @default_poll_interval_ms)
      |> Polling.normalize_interval_ms()

    app_opts =
      [
        route: route,
        api_base_url: option_or_config(opts, :api_base_url, config, @default_api_base_url),
        tenant_id: option_or_config(opts, :tenant_id, config, "workspace-local"),
        actor_id: option_or_config(opts, :actor_id, config, "operator-1"),
        participant_id: identity.participant_id,
        participant_role: identity.participant_role,
        authority_level: identity.authority_level,
        poll_interval_ms: poll_interval_ms,
        embedded: Keyword.get(opts, :embedded),
        embedded_module: Keyword.get(opts, :embedded_module, JidoHiveClient.RoomSession),
        event_log_poller_module:
          Keyword.get(opts, :event_log_poller_module, JidoHiveConsole.EventLogPoller),
        operator_module: operator_module,
        name: Keyword.get(opts, :name, nil),
        test_mode: Keyword.get(opts, :test_mode)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case App.start_link(app_opts) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
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
