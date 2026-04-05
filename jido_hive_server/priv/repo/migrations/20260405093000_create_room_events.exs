defmodule JidoHiveServer.Repo.Migrations.CreateRoomEvents do
  use Ecto.Migration

  def change do
    create table(:room_events) do
      add :event_id, :string, null: false
      add :room_id, :string, null: false
      add :event_type, :string, null: false
      add :causation_id, :string
      add :correlation_id, :string
      add :payload, :map, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:room_events, [:event_id])
    create index(:room_events, [:room_id, :inserted_at])
  end
end
