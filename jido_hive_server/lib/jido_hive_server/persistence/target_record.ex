defmodule JidoHiveServer.Persistence.TargetRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:target_id, :string, autogenerate: false}

  schema "target_registrations" do
    field(:workspace_id, :string)
    field(:participant_id, :string)
    field(:participant_role, :string)
    field(:capability_id, :string)
    field(:runtime_driver, :string)
    field(:provider, :string)
    field(:workspace_root, :string)
    field(:status, :string)
    field(:snapshot, :map)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :target_id,
      :workspace_id,
      :participant_id,
      :participant_role,
      :capability_id,
      :runtime_driver,
      :provider,
      :workspace_root,
      :status,
      :snapshot
    ])
    |> validate_required([
      :target_id,
      :workspace_id,
      :participant_id,
      :participant_role,
      :capability_id,
      :status,
      :snapshot
    ])
  end
end
