defmodule JidoHiveServer.Repo.Migrations.CreateJidoHivePersistence do
  use Ecto.Migration

  def change do
    create table(:room_snapshots, primary_key: false) do
      add :room_id, :string, primary_key: true
      add :snapshot, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:target_registrations, primary_key: false) do
      add :target_id, :string, primary_key: true
      add :workspace_id, :string, null: false
      add :participant_id, :string, null: false
      add :participant_role, :string, null: false
      add :capability_id, :string, null: false
      add :runtime_driver, :string
      add :provider, :string
      add :workspace_root, :string
      add :status, :string, null: false
      add :snapshot, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:target_registrations, [:workspace_id, :status])

    create table(:publication_runs, primary_key: false) do
      add :publication_run_id, :string, primary_key: true
      add :room_id, :string, null: false
      add :channel, :string, null: false
      add :connector_id, :string, null: false
      add :capability_id, :string, null: false
      add :status, :string, null: false
      add :request, :map, null: false
      add :result, :map
      add :error, :map

      timestamps(type: :utc_datetime_usec)
    end

    create index(:publication_runs, [:room_id, :inserted_at])
  end
end
