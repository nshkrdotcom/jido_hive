defmodule JidoHiveServer.Persistence.PublicationRunRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:publication_run_id, :string, autogenerate: false}

  schema "publication_runs" do
    field(:room_id, :string)
    field(:channel, :string)
    field(:connector_id, :string)
    field(:capability_id, :string)
    field(:status, :string)
    field(:request, :map)
    field(:result, :map)
    field(:error, :map)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :publication_run_id,
      :room_id,
      :channel,
      :connector_id,
      :capability_id,
      :status,
      :request,
      :result,
      :error
    ])
    |> validate_required([
      :publication_run_id,
      :room_id,
      :channel,
      :connector_id,
      :capability_id,
      :status,
      :request
    ])
  end
end
