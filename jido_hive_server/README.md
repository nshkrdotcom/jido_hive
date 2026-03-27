# JidoHiveServer

`jido_hive_server` is the Phoenix coordination server for `jido_hive`.

It owns rooms, referee planning, the shared collaboration envelope, durable room
snapshots, relay target registration, and direct GitHub/Notion publication
execution through `Jido.Integration.V2`.

## What It Exposes

- websocket relay at `/socket`
- room API:
  - `POST /api/rooms`
  - `GET /api/rooms/:id`
  - `POST /api/rooms/:id/run`
  - `GET /api/rooms/:id/publication_plan`
  - `POST /api/rooms/:id/publications`
  - `GET /api/rooms/:id/publications`
- connector operator API:
  - `GET /api/connectors/:connector_id/connections`
  - `POST /api/connectors/:connector_id/installs`
  - `GET /api/connectors/installs/:install_id`
  - `POST /api/connectors/installs/:install_id/complete`
- target discovery:
  - `GET /api/targets`

`POST /api/rooms/:id/run` accepts:

- `max_turns`
- `turn_timeout_ms`

## Persistence

The server uses SQLite through Ecto for:

- durable room snapshots
- target registrations
- publication run history

The repo-level `bin/server` wrapper runs `mix ecto.create` and `mix ecto.migrate`
before starting Phoenix.

For the guided operator flow around installs, connections, and publication
execution, use the root setup toolkit in
[../setup/README.md](../setup/README.md).

## Dev

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
mix test
mix quality
```
