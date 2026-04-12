defmodule JidoHiveServer.Persistence.RoomRunRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:run_id, :string, autogenerate: false}

  schema "room_runs" do
    field(:room_id, :string)
    field(:status, :string)
    field(:max_assignments, :integer)
    field(:assignments_started, :integer)
    field(:assignments_completed, :integer)
    field(:assignment_timeout_ms, :integer)
    field(:until, :map)
    field(:result, :map)
    field(:error, :map)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :run_id,
      :room_id,
      :status,
      :max_assignments,
      :assignments_started,
      :assignments_completed,
      :assignment_timeout_ms,
      :until,
      :result,
      :error
    ])
    |> validate_required([
      :run_id,
      :room_id,
      :status,
      :max_assignments,
      :assignments_started,
      :assignments_completed,
      :assignment_timeout_ms,
      :until
    ])
  end
end
