defmodule JidoHiveTermuiConsole.Config do
  @moduledoc false

  @default_api_base_url "http://127.0.0.1:4000/api"

  @spec ensure_initialized() :: :ok
  def ensure_initialized do
    File.mkdir_p!(config_dir())
    write_if_missing(config_path(), default_config())
    write_if_missing(rooms_path(), %{"rooms" => []})
    :ok
  end

  @spec config_dir() :: String.t()
  def config_dir do
    Application.get_env(:jido_hive_termui_console, :config_dir) ||
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

  @spec list_rooms() :: [String.t()]
  def list_rooms, do: load_rooms()

  @spec load_rooms() :: [String.t()]
  def load_rooms do
    rooms_path()
    |> read_json(%{"rooms" => []})
    |> Map.get("rooms", [])
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  @spec add_room(String.t()) :: :ok | {:error, term()}
  def add_room(room_id) when is_binary(room_id) do
    room_id = String.trim(room_id)

    if room_id == "" do
      {:error, :invalid_room_id}
    else
      current = load_rooms()
      write_json(rooms_path(), %{"rooms" => Enum.uniq(current ++ [room_id])})
    end
  end

  @spec remove_room(String.t()) :: :ok | {:error, term()}
  def remove_room(room_id) when is_binary(room_id) do
    rooms =
      load_rooms()
      |> Enum.reject(&(&1 == room_id))

    write_json(rooms_path(), %{"rooms" => rooms})
  end

  defp default_config do
    %{
      "api_base_url" => @default_api_base_url,
      "participant_id" => nil,
      "participant_role" => "coordinator",
      "authority_level" => "binding",
      "poll_interval_ms" => 500
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
end
