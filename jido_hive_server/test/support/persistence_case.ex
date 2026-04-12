defmodule JidoHiveServer.PersistenceCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias JidoHiveServer.Persistence.{
    PublicationRunRecord,
    RoomEventRecord,
    RoomRunRecord,
    RoomSnapshotRecord,
    TargetRecord
  }

  alias JidoHiveServer.Repo

  using do
    quote do
      setup do
        JidoHiveServer.PersistenceCase.reset_repo!()
        :ok
      end
    end
  end

  def reset_repo! do
    Repo.delete_all(PublicationRunRecord)
    Repo.delete_all(RoomEventRecord)
    Repo.delete_all(RoomRunRecord)
    Repo.delete_all(RoomSnapshotRecord)
    Repo.delete_all(TargetRecord)
    :ok
  end
end
