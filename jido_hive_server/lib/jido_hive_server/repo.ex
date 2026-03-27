defmodule JidoHiveServer.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :jido_hive_server,
    adapter: Ecto.Adapters.SQLite3
end
