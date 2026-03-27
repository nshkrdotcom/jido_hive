alias JidoHiveServer.Repo

{:ok, _} = Application.ensure_all_started(:jido_hive_server)

Ecto.Migrator.with_repo(Repo, fn repo ->
  Ecto.Migrator.run(repo, Application.app_dir(:jido_hive_server, "priv/repo/migrations"), :up,
    all: true
  )
end)

ExUnit.start()
