defmodule JidoHiveClient.Operator.Config do
  @moduledoc false

  @default_api_base_url "http://127.0.0.1:4000/api"

  @spec ensure_initialized() :: :ok
  def ensure_initialized do
    File.mkdir_p!(config_dir())
    write_if_missing(config_path(), default_config())
    write_if_missing(rooms_path(), %{"rooms" => []})
    write_if_missing(credentials_path(), %{})
    :ok
  end

  @spec config_dir() :: String.t()
  def config_dir do
    Application.get_env(:jido_hive_client, :config_dir) ||
      Path.join([System.user_home!(), ".config", "hive"])
  end

  @spec config_path() :: String.t()
  def config_path, do: Path.join(config_dir(), "config.json")

  @spec rooms_path() :: String.t()
  def rooms_path, do: Path.join(config_dir(), "rooms.json")

  @spec credentials_path() :: String.t()
  def credentials_path, do: Path.join(config_dir(), "credentials.json")

  @spec load() :: map()
  def load do
    default_config()
    |> Map.merge(read_json(config_path(), default_config()))
  end

  @spec load_rooms() :: [String.t()]
  def load_rooms do
    rooms_path()
    |> read_json(%{"rooms" => []})
    |> legacy_rooms()
  end

  @spec load_rooms(String.t()) :: [String.t()]
  def load_rooms(api_base_url) when is_binary(api_base_url) do
    rooms_path()
    |> read_json(%{"rooms_by_api_base_url" => %{}})
    |> namespaced_rooms(api_base_url)
  end

  @spec add_room(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def add_room(room_id, api_base_url \\ nil) when is_binary(room_id) do
    room_id = String.trim(room_id)

    if room_id == "" do
      {:error, :invalid_room_id}
    else
      payload = read_json(rooms_path(), %{"rooms_by_api_base_url" => %{}, "rooms" => []})

      next_payload =
        if is_binary(api_base_url) and String.trim(api_base_url) != "" do
          normalized_api_base_url = normalize_api_base_url(api_base_url)

          rooms =
            payload
            |> namespaced_rooms(normalized_api_base_url)
            |> Kernel.++([room_id])
            |> Enum.uniq()

          payload
          |> Map.put(
            "rooms_by_api_base_url",
            Map.put(rooms_by_api_base_url(payload), normalized_api_base_url, rooms)
          )
          |> Map.put("rooms", legacy_rooms(payload) |> Enum.reject(&(&1 == room_id)))
        else
          Map.put(payload, "rooms", (legacy_rooms(payload) ++ [room_id]) |> Enum.uniq())
        end

      write_json(rooms_path(), next_payload)
    end
  end

  @spec remove_room(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def remove_room(room_id, api_base_url \\ nil) when is_binary(room_id) do
    payload = read_json(rooms_path(), %{"rooms_by_api_base_url" => %{}, "rooms" => []})

    next_payload =
      if is_binary(api_base_url) and String.trim(api_base_url) != "" do
        normalized_api_base_url = normalize_api_base_url(api_base_url)

        rooms =
          payload
          |> namespaced_rooms(normalized_api_base_url)
          |> Enum.reject(&(&1 == room_id))

        payload
        |> Map.put(
          "rooms_by_api_base_url",
          Map.put(rooms_by_api_base_url(payload), normalized_api_base_url, rooms)
        )
        |> Map.put("rooms", legacy_rooms(payload) |> Enum.reject(&(&1 == room_id)))
      else
        Map.put(payload, "rooms", legacy_rooms(payload) |> Enum.reject(&(&1 == room_id)))
      end

    write_json(rooms_path(), next_payload)
  end

  @spec write_credentials(map()) :: :ok | {:error, term()}
  def write_credentials(credentials) when is_map(credentials) do
    :ok = ensure_initialized()

    with :ok <- write_json(credentials_path(), credentials),
         :ok <- :file.change_mode(String.to_charlist(credentials_path()), 0o600) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec load_credentials() :: map()
  def load_credentials do
    read_json(credentials_path(), %{})
  end

  defp default_config do
    %{
      "api_base_url" => @default_api_base_url,
      "participant_id" => nil,
      "participant_role" => "coordinator",
      "authority_level" => "binding",
      "poll_interval_ms" => JidoHiveClient.Polling.default_interval_ms(),
      "tenant_id" => "workspace-local",
      "actor_id" => "operator-1"
    }
  end

  defp write_if_missing(path, payload) do
    unless File.exists?(path) do
      :ok = write_json(path, payload)
    end
  end

  defp read_json(path, fallback) do
    case File.read(path) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, decoded} when is_map(decoded) -> decoded
          _other -> fallback
        end

      {:error, _reason} ->
        fallback
    end
  rescue
    _error -> fallback
  end

  defp write_json(path, payload) do
    File.write(path, Jason.encode!(payload, pretty: true))
  end

  defp namespaced_rooms(payload, api_base_url) do
    payload
    |> rooms_by_api_base_url()
    |> Map.get(normalize_api_base_url(api_base_url), [])
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp legacy_rooms(payload) do
    payload
    |> Map.get("rooms", [])
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp rooms_by_api_base_url(payload) do
    case Map.get(payload, "rooms_by_api_base_url", %{}) do
      map when is_map(map) -> map
      _other -> %{}
    end
  end

  defp normalize_api_base_url(api_base_url) do
    api_base_url
    |> to_string()
    |> String.trim()
    |> String.trim_trailing("/")
  end
end
