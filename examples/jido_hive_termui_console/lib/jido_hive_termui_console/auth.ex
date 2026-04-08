defmodule JidoHiveTermuiConsole.Auth do
  @moduledoc false

  alias JidoHiveTermuiConsole.Config

  @channels ~w[github notion]

  @spec load_all() :: map()
  def load_all do
    credentials = load_credentials()

    Enum.into(@channels, %{}, fn channel ->
      {channel, status_for(channel, credentials)}
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
