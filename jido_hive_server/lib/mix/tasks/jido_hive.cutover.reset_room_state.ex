defmodule Mix.Tasks.JidoHive.Cutover.ResetRoomState do
  @moduledoc false
  @shortdoc "Deletes incompatible persisted room-core rows before the canonical cutover boot"

  use Mix.Task

  alias Ecto.Adapters.SQL
  alias JidoHiveServer.Repo

  @tables ~w[room_runs run_operations publication_runs room_events room_snapshots]

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    existing_tables = existing_tables()

    Enum.each(@tables, fn table ->
      if table in existing_tables do
        SQL.query!(Repo, "DELETE FROM #{table}", [])
        Mix.shell().info("cleared #{table}")
      end
    end)
  end

  defp existing_tables do
    SQL.query!(
      Repo,
      "SELECT name FROM sqlite_master WHERE type = 'table'",
      []
    ).rows
    |> Enum.map(fn [name] -> name end)
  end
end
