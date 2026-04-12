defmodule JidoHivePublications.PersistenceCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias JidoHivePublications.{Infrastructure, PublicationRun}
  alias JidoHiveServer.Repo

  using do
    quote do
      setup do
        JidoHivePublications.PersistenceCase.reset_publication_runs!()
        :ok
      end
    end
  end

  def reset_publication_runs! do
    Infrastructure.ensure_repo_started!()
    Repo.delete_all(PublicationRun)
    :ok
  end
end
