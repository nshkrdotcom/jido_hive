# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :jido_hive_server,
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  turn_wait_timeout_ms: 180_000,
  turn_wait_poll_ms: 250,
  ecto_repos: [JidoHiveServer.Repo]

config :jido_hive_server, JidoHiveServer.Repo,
  adapter: Ecto.Adapters.SQLite3,
  migration_primary_key: [type: :string, autogenerate: false],
  migration_timestamps: [type: :utc_datetime_usec]

# Configure the endpoint
config :jido_hive_server, JidoHiveServerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: JidoHiveServerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: JidoHiveServer.PubSub,
  live_view: [signing_salt: "NWRjk/5e"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
