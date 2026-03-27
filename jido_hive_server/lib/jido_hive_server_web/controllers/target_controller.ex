defmodule JidoHiveServerWeb.TargetController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.RemoteExec

  def index(conn, _params) do
    targets =
      RemoteExec.list_targets()
      |> Enum.map(&public_target/1)
      |> Enum.sort_by(& &1.participant_id)

    json(conn, %{data: targets})
  end

  defp public_target(target) do
    Map.take(target, [
      :target_id,
      :capability_id,
      :workspace_id,
      :user_id,
      :participant_id,
      :participant_role,
      :runtime_driver,
      :provider,
      :workspace_root
    ])
  end
end
