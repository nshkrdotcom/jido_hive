import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :jido_hive_server, JidoHiveServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ppeB9jid2nqWqC4jgH9GxVIduzOcG1aTnhc43mwBjyOiYbSDuDWKhz7ezhm1fRsk",
  server: true

config :jido_hive_server, JidoHiveServer.Repo,
  database: Path.expand("../tmp/jido_hive_server_test.db", __DIR__),
  pool_size: 5

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
