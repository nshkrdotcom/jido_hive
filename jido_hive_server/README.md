# JidoHiveServer

`jido_hive_server` is the Phoenix server that runs the shared side of `jido_hive`.

It is responsible for:

- exposing the public `REST` API
- accepting worker connections over Phoenix WebSockets
- registering targets
- creating and running rooms
- applying workflow logic
- persisting room snapshots and room events
- planning and executing publications

If you are new to the repo, start with the root guide first: [../README.md](../README.md)

## What end users should know

From an operator point of view, the server is the source of truth.

If you want to:

- create rooms
- run workflows
- inspect room state
- inspect target availability
- inspect room history
- publish completed outputs

you are using the server app.

Workers connect to the server, but workers do not own the collaboration lifecycle.

## Quick local start

From the repo root, the recommended startup path is:

```bash
bin/server
```

That wrapper runs:

- `mix ecto.create`
- `mix ecto.migrate`
- `mix phx.server`

You can also run directly inside this app:

```bash
cd jido_hive_server
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

Default local endpoint:

- `http://127.0.0.1:4000`

## What the server exposes

### WebSocket relay

Relay endpoint:

- `ws://127.0.0.1:4000/socket/websocket`

This is used by worker clients to:

- join a relay topic
- register connections and targets
- receive `job.start`
- send back `job.result`

### REST API

Base local API:

- `http://127.0.0.1:4000/api`

Key endpoints:

- `GET /api/targets`
- `GET /api/workflows`
- `GET /api/workflows/*id`
- `POST /api/rooms`
- `GET /api/rooms/:id`
- `GET /api/rooms/:id/events`
- `GET /api/rooms/:id/timeline`
- `GET /api/rooms/:id/timeline?after=<cursor>`
- `GET /api/rooms/:id/timeline?stream=true`
- `GET /api/rooms/:id/timeline?stream=true&once=true`
- `POST /api/rooms/:id/run`
- `POST /api/rooms/:id/first_slice`
- `GET /api/rooms/:id/publication_plan`
- `GET /api/rooms/:id/publications`
- `POST /api/rooms/:id/publications`
- `GET /api/connectors/:connector_id/connections`
- `POST /api/connectors/:connector_id/installs`
- `GET /api/connectors/installs/:install_id`
- `POST /api/connectors/installs/:install_id/complete`

## Room execution model

The server runs collaboration through rooms and workflows.

High-level flow:

1. workers connect and register targets
2. a room is created
3. the server chooses a workflow
4. the server dispatches turns to targets
5. clients execute and return structured results
6. the server reduces those results into room state
7. the server can prepare and execute publications

For UI and operator history views, the server also exposes a room timeline projection derived from persisted room events.

Default workflow behavior is a structured round-robin collaboration pattern with proposal, critique, and resolution phases. The generalized substrate also supports additional workflow definitions, including chain-of-responsibility.

## Room history surfaces

The server exposes two different history views for a room:

- `GET /api/rooms/:id/events`: the low-level persisted room event history
- `GET /api/rooms/:id/timeline`: the UI-facing timeline projection derived from those events

Use the timeline endpoint when you want:

- human-readable room activity
- incremental polling with `?after=<cursor>`
- SSE delivery with `?stream=true`
- one-shot backlog streaming with `?stream=true&once=true`

Use the raw events endpoint when you want the underlying event records rather than the projection.

## Persistence

The server uses SQLite through Ecto.

Persisted server data includes:

- room snapshots
- room events
- target registrations
- publication runs

This is what lets the server act as the durable shared state holder instead of treating the relay as an ephemeral pass-through.

## Publications

The server owns publication planning and execution.

That includes:

- turning final room state into publication payloads
- using configured connector installations
- recording publication run history

For operator-oriented publication commands, use the repo-level toolkit:

- [../setup/README.md](../setup/README.md)

## What developers should know

The server is not just a Phoenix transport shell. The generalized refactor moved the collaboration model toward:

- explicit room command and room event structures
- pure event reduction into snapshots
- workflow registry and workflow modules
- thinner relay and controller boundaries

Design split:

- controllers and channels are boundaries
- orchestration lives in collaboration and persistence modules
- workflows define the ordered execution behavior

That structure is what future UI and workflow work should build on.

## Production and deployment

Current deployed base:

- `https://jido-hive-server-test.app.nsai.online`

For the exact end-to-end production operator runbook, including log tailing and starting production workers, use the root production section:

- [../README.md#production-smoke-test](../README.md#production-smoke-test)

Deployments run through `coolify_ex` in `MIX_ENV=coolify`.

Typical deploy path from repo root:

```bash
scripts/deploy_coolify.sh
```

Useful follow-up commands:

```bash
cd jido_hive_server
MIX_ENV=coolify mix coolify.latest --project server
MIX_ENV=coolify mix coolify.status --project server --latest
MIX_ENV=coolify mix coolify.logs --project server --latest --tail 200
MIX_ENV=coolify mix coolify.app_logs --project server --lines 200 --follow
```

## Development

Inside this app:

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
mix test
mix quality
```

Repo-wide from the root:

```bash
mix ci
```

## Related docs

- root guide: [../README.md](../README.md)
- setup toolkit: [../setup/README.md](../setup/README.md)
- architecture: [../docs/architecture.md](../docs/architecture.md)
- round-robin developer guide: [../docs/developer/multi_agent_round_robin.md](../docs/developer/multi_agent_round_robin.md)
