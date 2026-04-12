defmodule JidoHivePublications.Storage do
  @moduledoc false

  import Ecto.Query

  alias JidoHivePublications.{Infrastructure, PublicationRun}
  alias JidoHiveServer.Repo

  @spec create_run(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def create_run(attrs) when is_map(attrs) do
    Infrastructure.ensure_repo_started!()
    normalized = normalize(attrs)

    %PublicationRun{}
    |> PublicationRun.changeset(normalized)
    |> Repo.insert()
    |> case do
      {:ok, record} -> {:ok, run_snapshot(record)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec update_run(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_run(publication_run_id, attrs)
      when is_binary(publication_run_id) and is_map(attrs) do
    Infrastructure.ensure_repo_started!()

    case Repo.get(PublicationRun, publication_run_id) do
      nil ->
        {:error, :publication_run_not_found}

      %PublicationRun{} = record ->
        record
        |> PublicationRun.changeset(normalize(attrs))
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, run_snapshot(updated)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @spec fetch_run(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_run(room_id, publication_run_id)
      when is_binary(room_id) and is_binary(publication_run_id) do
    Infrastructure.ensure_repo_started!()

    case Repo.get(PublicationRun, publication_run_id) do
      %PublicationRun{room_id: ^room_id} = record -> {:ok, run_snapshot(record)}
      %PublicationRun{} -> {:error, :publication_run_not_found}
      nil -> {:error, :publication_run_not_found}
    end
  end

  @spec list_runs(String.t()) :: [map()]
  def list_runs(room_id) when is_binary(room_id) do
    Infrastructure.ensure_repo_started!()

    from(record in PublicationRun,
      where: record.room_id == ^room_id,
      order_by: [desc: record.inserted_at, desc: record.publication_run_id]
    )
    |> Repo.all()
    |> Enum.map(&run_snapshot/1)
  end

  defp run_snapshot(%PublicationRun{} = record) do
    %{
      id: record.publication_run_id,
      room_id: record.room_id,
      channel: record.channel,
      connector_id: record.connector_id,
      capability_id: record.capability_id,
      status: record.status,
      request: record.request || %{},
      result: record.result || %{},
      error: record.error || %{},
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    }
  end

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(%_{} = value), do: value |> Map.from_struct() |> normalize()

  defp normalize(value) when is_map(value) do
    Map.new(value, fn {key, inner} -> {key, normalize(inner)} end)
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value), do: value
end
