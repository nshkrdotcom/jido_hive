defmodule JidoHivePublications.PublicationRun do
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

  @type t :: %__MODULE__{
          publication_run_id: String.t() | nil,
          room_id: String.t() | nil,
          channel: String.t() | nil,
          connector_id: String.t() | nil,
          capability_id: String.t() | nil,
          status: String.t() | nil,
          request: map() | nil,
          result: map() | nil,
          error: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
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
