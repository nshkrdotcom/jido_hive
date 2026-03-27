defmodule JidoHiveServer.Persistence.RoomSnapshotRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:room_id, :string, autogenerate: false}

  schema "room_snapshots" do
    field(:snapshot, :map)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:room_id, :snapshot])
    |> validate_required([:room_id, :snapshot])
  end
end
