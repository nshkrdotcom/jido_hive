defmodule JidoHiveTermuiConsole.Auth do
  @moduledoc false

  alias JidoHiveTermuiConsole.{Config, HTTP}

  @channels ~w[github notion]

  @spec load_all() :: map()
  def load_all do
    credentials = load_credentials()

    Enum.into(@channels, %{}, fn channel ->
      {channel, status_for(channel, credentials)}
    end)
  end

  @spec load_all(String.t() | nil, String.t() | nil, module()) :: map()
  def load_all(api_base_url, subject, http_module \\ HTTP)

  def load_all(api_base_url, subject, http_module)
      when is_binary(api_base_url) and api_base_url != "" and is_binary(subject) and subject != "" do
    credentials = load_credentials()

    Enum.into(@channels, %{}, fn channel ->
      {channel, fetch_remote_state(api_base_url, subject, channel, http_module, credentials)}
    end)
  end

  def load_all(_api_base_url, _subject, _http_module) do
    credentials = load_credentials()

    Enum.into(@channels, %{}, fn channel ->
      {channel, local_state(channel, credentials)}
    end)
  end

  @spec cached?(String.t()) :: boolean()
  def cached?(channel), do: load_all()[channel] == :cached

  @spec connection_id(String.t()) :: String.t() | nil
  def connection_id(channel) when is_binary(channel) do
    case Map.get(load_credentials(), channel) do
      %{"connection_id" => connection_id} = credential when is_binary(connection_id) ->
        if expired?(credential), do: nil, else: connection_id

      _other ->
        nil
    end
  end

  @spec connection_id(map(), String.t()) :: String.t() | nil
  def connection_id(auth_state, channel) when is_map(auth_state) and is_binary(channel) do
    case Map.get(auth_state, channel) do
      %{connection_id: connection_id} when is_binary(connection_id) and connection_id != "" ->
        connection_id

      %{"connection_id" => connection_id} when is_binary(connection_id) and connection_id != "" ->
        connection_id

      _other ->
        nil
    end
  end

  @spec status(map(), String.t()) :: :cached | :missing | :pending
  def status(auth_state, channel) when is_map(auth_state) and is_binary(channel) do
    case Map.get(auth_state, channel) do
      %{status: status} when status in [:cached, :missing, :pending] -> status
      %{"status" => status} when status in [:cached, :missing, :pending] -> status
      _other -> :missing
    end
  end

  @spec save(String.t(), map()) :: :ok | {:error, term()}
  def save(channel, credential), do: store(channel, credential)

  @spec store(String.t(), map()) :: :ok | {:error, term()}
  def store(channel, credential) when is_binary(channel) and is_map(credential) do
    :ok = Config.ensure_initialized()

    next_credentials =
      load_credentials()
      |> Map.put(channel, stringify_keys(credential))

    with :ok <-
           File.write(Config.credentials_path(), Jason.encode!(next_credentials, pretty: true)),
         :ok <- :file.change_mode(String.to_charlist(Config.credentials_path()), 0o600) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec start_device_flow(String.t()) :: {:ok, map()} | {:error, term()}
  def start_device_flow(channel) when channel in @channels do
    {:ok,
     %{
       channel: channel,
       user_code: random_code(),
       verification_uri: "https://auth.#{channel}.example/device"
     }}
  end

  def start_device_flow(channel), do: {:error, {:unsupported_channel, channel}}

  defp load_credentials do
    case File.read(Config.credentials_path()) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, decoded} when is_map(decoded) -> decoded
          _other -> %{}
        end

      {:error, _reason} ->
        %{}
    end
  rescue
    _error -> %{}
  end

  defp status_for(channel, credentials) do
    case Map.get(credentials, channel) do
      %{} = credential -> if(expired?(credential), do: :missing, else: :cached)
      _other -> :missing
    end
  end

  defp fetch_remote_state(api_base_url, subject, channel, http_module, credentials) do
    path = "/connectors/#{channel}/connections?subject=#{URI.encode_www_form(subject)}"

    case http_module.get(api_base_url, path) do
      {:ok, %{"data" => connections}} when is_list(connections) ->
        remote_state(connections)

      _other ->
        local_state(channel, credentials)
    end
  end

  defp remote_state(connections) do
    cond do
      connection = latest_connection(connections, &connected?/1) ->
        %{
          connection_id: Map.get(connection, "connection_id"),
          source: :server,
          state: Map.get(connection, "state", "connected"),
          status: :cached
        }

      connection = latest_connection(connections, &(not connected?(&1))) ->
        %{
          connection_id: Map.get(connection, "connection_id"),
          source: :server,
          state: Map.get(connection, "state"),
          status: :pending
        }

      true ->
        %{
          connection_id: nil,
          source: :server,
          state: nil,
          status: :missing
        }
    end
  end

  defp local_state(channel, credentials) do
    case Map.get(credentials, channel) do
      %{"connection_id" => connection_id} = credential
      when is_binary(connection_id) and connection_id != "" ->
        if expired?(credential) do
          missing_state()
        else
          %{
            connection_id: connection_id,
            source: :local,
            state: "cached",
            status: :cached
          }
        end

      _other ->
        missing_state()
    end
  end

  defp latest_connection(connections, predicate) do
    connections
    |> Enum.filter(predicate)
    |> Enum.max_by(&connection_timestamp/1, fn -> nil end)
  end

  defp connected?(connection), do: Map.get(connection, "state") == "connected"

  defp connection_timestamp(connection) do
    Map.get(connection, "updated_at") || Map.get(connection, "inserted_at") || ""
  end

  defp missing_state do
    %{
      connection_id: nil,
      source: :missing,
      state: nil,
      status: :missing
    }
  end

  defp expired?(%{"expires_at" => expires_at}) when is_binary(expires_at) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, datetime, _offset} -> DateTime.compare(datetime, DateTime.utc_now()) == :lt
      _other -> false
    end
  end

  defp expired?(_credential), do: false

  defp random_code do
    4
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :upper)
    |> String.replace(~r/(....)(....)/, "\\1-\\2")
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
