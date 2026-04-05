defmodule JidoHiveServer.Persistence.RoomEventRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "room_events" do
    field(:event_id, :string)
    field(:room_id, :string)
    field(:event_type, :string)
    field(:causation_id, :string)
    field(:correlation_id, :string)
    field(:payload, :map)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:event_id, :room_id, :event_type, :causation_id, :correlation_id, :payload])
    |> validate_required([:event_id, :room_id, :event_type, :payload])
    |> unique_constraint(:event_id)
  end
end
