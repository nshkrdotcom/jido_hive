# JidoHiveServer

`jido_hive_server` is the Phoenix application that owns the shared side of `jido_hive`.

It is responsible for:

- exposing the public `REST` API
- accepting worker connections over Phoenix channels
- tracking available runtime targets
- creating and running rooms
- dispatching assignments under a policy
- persisting room snapshots and room events
- exposing room history and timeline views
- planning and executing publications

If you are new to the repo, start with the root guide first: [../README.md](../README.md)

## What end users and operators should know

From an operator point of view, the server is the source of truth.

Use the server when you need to:

- create a room
- inspect targets
- inspect or stream room history
- submit a manual human contribution
- run a room under a policy
- inspect or execute publications

Workers connect to the server, but workers do not own the collaboration lifecycle.

## Quick local start

From the repo root:

```bash
bin/server
```

That wrapper runs:

- `mix ecto.create`
- `mix ecto.migrate`
- `mix phx.server`

Direct app-local startup:

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

### Phoenix relay

Local relay endpoint:

- `ws://127.0.0.1:4000/socket/websocket`

Canonical relay events:

- client joins relay topic
- client pushes `relay.hello`
- client pushes `participant.upsert`
- server pushes `assignment.start`
- client pushes `contribution.submit`

The relay is for live assignment delivery and contribution intake. Shared state still lives on the server.

### REST API

Local base API:

- `http://127.0.0.1:4000/api`

Routes:

- `GET /api/targets`
- `GET /api/policies`
- `GET /api/policies/*id`
- `POST /api/rooms`
- `GET /api/rooms/:id`
- `GET /api/rooms/:id/events`
- `GET /api/rooms/:id/timeline`
- `GET /api/rooms/:id/timeline?after=<cursor>`
- `GET /api/rooms/:id/timeline?stream=true`
- `GET /api/rooms/:id/timeline?stream=true&once=true`
- `GET /api/rooms/:id/context_objects`
- `GET /api/rooms/:id/context_objects/:context_id`
- `POST /api/rooms/:id/contributions`
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

The server runs collaboration through rooms, policies, assignments, and contributions.

High-level flow:

1. workers connect and upsert participants/targets
2. a room is created
3. a dispatch policy is selected
4. the server opens the next assignment
5. a worker executes locally and publishes a contribution
6. the server reduces that contribution into room state
7. the room timeline and publication plan update from persisted events

A room snapshot is built from generic collaboration primitives rather than workflow-specific state.

## Built-in policies

Current built-in policies:

- `round_robin/v2`: fixed structured collaboration across the locked participant set
- `resource_pool/v1`: allocate assignments to the least-used available runtime participant
- `human_gate/v1`: stop for human/manual contributions and completion gating

Use `GET /api/policies` to inspect the available policy definitions.

## Manual contributions

The server accepts human/manual contributions over HTTP.

Example use cases:

- an operator injects a decision
- a reviewer adds a question or constraint
- a UI submits a binding approval step

Route:

- `POST /api/rooms/:id/contributions`

That path uses the same canonical contribution model as worker-submitted contributions.

## History surfaces

The server exposes two room history views:

- `GET /api/rooms/:id/events`: persisted room event records
- `GET /api/rooms/:id/timeline`: UI-facing projection derived from those events

Use the timeline when you want:

- human-readable activity
- incremental polling with `?after=<cursor>`
- SSE streaming with `?stream=true`

Use the raw event log when you want the lower-level event stream or debugging detail.

## Persistence

The server uses SQLite through Ecto.

Persisted data includes:

- room snapshots
- room events
- target registrations
- publication runs

Normal local startup runs migrations automatically through `bin/server`.

## Publications

The server owns publication planning and execution.

That includes:

- GitHub publication actions
- Notion publication actions
- publication-run persistence

The built-in publication integrations are registered through the integrations bootstrap process.

## What developers should know

The server design is intentionally layered:

- collaboration schema modules define the room primitives
- reducer and command-handler modules own pure state transitions
- dispatch policies select assignments without transport concerns
- persistence and remote execution adapt the pure core to storage and relay boundaries
- controllers and channels remain thin boundaries

Important server modules live under:

- `lib/jido_hive_server/collaboration`
- `lib/jido_hive_server/persistence.ex`
- `lib/jido_hive_server/remote_exec.ex`
- `lib/jido_hive_server/publications.ex`

## Production and deployment

Current deployed base:

- `https://jido-hive-server-test.app.nsai.online`

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

For the exact production operator sequence, use the root guide:

- [../README.md#production-smoke-test](../README.md#production-smoke-test)

## Development

Inside this app:

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
mix test
mix docs --warnings-as-errors
```

Repo-wide from the root:

```bash
mix ci
```
