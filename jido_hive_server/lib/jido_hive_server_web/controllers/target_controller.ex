defmodule JidoHiveServerWeb.TargetController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.Persistence
  alias JidoHiveServerWeb.API

  def index(conn, _params) do
    targets =
      Persistence.list_targets(status: "online")
      |> Enum.sort_by(& &1.target_id)

    json(conn, API.data(targets))
  end

  def create(conn, %{"data" => attrs}) do
    case Persistence.upsert_target(normalize_target_attrs(attrs)) do
      {:ok, target} ->
        conn
        |> put_status(:created)
        |> json(API.data(target))

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_target", inspect(reason))
    end
  end

  def create(conn, _params) do
    render_error(conn, :unprocessable_entity, "invalid_target", "expected data payload")
  end

  def delete(conn, %{"target_id" => target_id}) do
    :ok = Persistence.mark_target_offline(target_id)
    json(conn, API.data(%{"target_id" => target_id, "status" => "offline"}))
  end

  defp normalize_target_attrs(attrs) do
    %{
      target_id: Map.get(attrs, "target_id"),
      workspace_id: Map.get(attrs, "workspace_id", "workspace-local"),
      participant_id: Map.get(attrs, "participant_id"),
      participant_role: Map.get(attrs, "participant_role", "agent"),
      capability_id: Map.get(attrs, "capability_id"),
      runtime_driver: Map.get(attrs, "runtime_driver"),
      provider: Map.get(attrs, "provider"),
      workspace_root: Map.get(attrs, "workspace_root"),
      user_id: Map.get(attrs, "user_id")
    }
  end

  defp render_error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(API.error(code, message))
  end
end
