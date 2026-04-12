defmodule JidoHiveServer.Repo.Migrations.AddCanonicalRoomEventSequenceAndRoomRuns do
  use Ecto.Migration

  def up do
    unless column_exists?("room_events", "sequence") do
      execute("ALTER TABLE room_events ADD COLUMN sequence INTEGER")
    end

    execute("""
    WITH ranked AS (
      SELECT id,
             ROW_NUMBER() OVER (
               PARTITION BY room_id
               ORDER BY inserted_at ASC, id ASC
             ) AS seq
      FROM room_events
    )
    UPDATE room_events
    SET sequence = (
      SELECT ranked.seq
      FROM ranked
      WHERE ranked.id = room_events.id
    )
    WHERE sequence IS NULL
    """)

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS room_events_room_id_sequence_index
    ON room_events (room_id, sequence)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS room_events_room_id_sequence_lookup_index
    ON room_events (room_id, sequence)
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS room_runs (
      run_id TEXT PRIMARY KEY,
      room_id TEXT NOT NULL,
      status TEXT NOT NULL,
      max_assignments INTEGER NOT NULL,
      assignments_started INTEGER NOT NULL,
      assignments_completed INTEGER NOT NULL,
      assignment_timeout_ms INTEGER NOT NULL,
      until MAP NOT NULL,
      result MAP,
      error MAP,
      inserted_at TEXT,
      updated_at TEXT
    )
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS room_runs_room_id_inserted_at_index
    ON room_runs (room_id, inserted_at)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS room_runs_room_id_status_index
    ON room_runs (room_id, status)
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS room_runs_room_id_status_index")
    execute("DROP INDEX IF EXISTS room_runs_room_id_inserted_at_index")
    execute("DROP TABLE IF EXISTS room_runs")
    execute("DROP INDEX IF EXISTS room_events_room_id_sequence_lookup_index")
    execute("DROP INDEX IF EXISTS room_events_room_id_sequence_index")
  end

  defp column_exists?(table, column) do
    repo()
    |> Ecto.Adapters.SQL.query!("PRAGMA table_info(#{table})", [])
    |> Map.fetch!(:rows)
    |> Enum.any?(fn [_cid, name | _rest] -> name == column end)
  end
end
