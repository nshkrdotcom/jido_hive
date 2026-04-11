defmodule JidoHiveWeb.UIConfig do
  @moduledoc false

  alias JidoHiveClient.RoomSession

  @app :jido_hive_web

  @spec api_base_url() :: String.t()
  def api_base_url do
    Application.fetch_env!(@app, :api_base_url)
  end

  @spec identity(map()) :: map()
  def identity(params \\ %{}) when is_map(params) do
    defaults = Application.fetch_env!(@app, :default_identity)

    %{
      subject: param_or_default(params, "subject", defaults.subject),
      participant_id: param_or_default(params, "participant_id", defaults.participant_id),
      participant_role: param_or_default(params, "participant_role", defaults.participant_role),
      authority_level: param_or_default(params, "authority_level", defaults.authority_level)
    }
  end

  @spec rooms_module() :: module()
  def rooms_module do
    Application.get_env(@app, :rooms_module, JidoHiveSurface)
  end

  @spec publications_module() :: module()
  def publications_module do
    Application.get_env(@app, :publications_module, JidoHiveSurface)
  end

  @spec room_session_module() :: module()
  def room_session_module do
    Application.get_env(@app, :room_session_module, RoomSession)
  end

  defp param_or_default(params, key, default) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> value
      _other -> default
    end
  end
end
