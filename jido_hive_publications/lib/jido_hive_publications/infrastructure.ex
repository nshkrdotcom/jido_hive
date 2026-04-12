defmodule JidoHivePublications.Infrastructure do
  @moduledoc false

  alias JidoHiveServer.Repo

  @ecto_repos_key :ecto_repos
  @repo_app :jido_hive_server

  @spec ensure_repo_started() :: :ok | {:error, term()}
  def ensure_repo_started do
    configure_repo()

    with {:ok, _} <- Application.ensure_all_started(:ecto_sqlite3),
         {:ok, _} <- start_repo() do
      :ok
    end
  end

  @spec ensure_repo_started!() :: :ok
  def ensure_repo_started! do
    case ensure_repo_started() do
      :ok -> :ok
      {:error, reason} -> raise "failed to start publication repo: #{inspect(reason)}"
    end
  end

  @spec migrate_repo!() :: :ok
  def migrate_repo! do
    ensure_repo_started!()

    Ecto.Migrator.with_repo(Repo, fn repo ->
      Ecto.Migrator.run(repo, Application.app_dir(:jido_hive_server, "priv/repo/migrations"), :up,
        all: true
      )
    end)

    :ok
  end

  defp configure_repo do
    Application.put_env(@repo_app, @ecto_repos_key, [Repo])

    repo_config =
      @repo_app
      |> Application.get_env(Repo, [])
      |> Keyword.put_new(:adapter, Ecto.Adapters.SQLite3)
      |> Keyword.put_new(:database, default_database_path())
      |> Keyword.put_new(:pool_size, 5)

    Application.put_env(@repo_app, Repo, repo_config)
  end

  defp start_repo do
    case Process.whereis(Repo) do
      nil -> Repo.start_link()
      _pid -> {:ok, :already_started}
    end
  end

  defp default_database_path do
    System.get_env("JIDO_HIVE_SERVER_DB") ||
      Application.get_env(:jido_hive_publications, :server_database) ||
      env_database_path()
  end

  defp env_database_path do
    env = current_env()

    case env do
      :test ->
        publication_tmp_path("jido_hive_publications_test.db")

      _other ->
        server_tmp_path("jido_hive_server_#{env}.db")
    end
  end

  defp publication_tmp_path(filename) do
    tmp_dir = Path.expand("../tmp", __DIR__)
    File.mkdir_p!(tmp_dir)
    Path.join(tmp_dir, filename)
  end

  defp server_tmp_path(filename) do
    build_app_dir = Application.app_dir(:jido_hive_server)
    source_dir = Path.expand("../../../../jido_hive_server", build_app_dir)

    tmp_dir =
      if File.dir?(source_dir) do
        Path.join(source_dir, "tmp")
      else
        Path.join(build_app_dir, "tmp")
      end

    File.mkdir_p!(tmp_dir)
    Path.join(tmp_dir, filename)
  end

  defp current_env do
    :jido_hive_publications
    |> Application.get_env(:server_env, System.get_env("MIX_ENV", "dev"))
    |> to_string()
    |> String.to_atom()
  end
end
