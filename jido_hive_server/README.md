# JidoHiveServer

`jido_hive_server` is the Phoenix application that owns the shared coordination side of `jido_hive`.

It is responsible for:

- the public `REST` control plane
- the Phoenix relay used by workers
- target registration and availability tracking
- room creation and room execution
- dispatch policy selection and assignment dispatch
- persistence of room snapshots and room events
- room timeline and room event history surfaces
- publication planning and publication execution

Start with the root guide first if you are onboarding: [../README.md](../README.md)

## What this app is for

From an operator or end-user point of view, the server is the system of record.

Use the server when you need to:

- inspect connected workers
- create a room
- run a room
- inspect room state
- inspect room timeline or raw events
- submit a manual human contribution
- inspect publication drafts
- execute publication actions

Workers never own the collaboration lifecycle. They only execute assignments.

## Quick start

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

Default local base URL:

- `http://127.0.0.1:4000`

## Runtime model

The server coordinates collaboration through these primitives.

### Room

The room is the top-level shared container.

A room tracks:

- `room_id`
- `brief`
- `rules`
- `participants`
- `assignments`
- `contributions`
- `context_objects`
- `dispatch_policy_id`
- `dispatch_policy_config`
- `dispatch_state`
- publication status and runs

### Participant

Participants are room actors.

Common participant classes:

- runtime workers advertising a relay target
- human reviewers or operators contributing over HTTP

### Assignment

Assignments are server-opened work items.

The built-in relay packet includes:

- `assignment_id`
- `room_id`
- `participant_id`
- `participant_role`
- `phase`
- `objective`
- `context_view`
- `contribution_contract`
- `session`

### Contribution

Contributions are server-ingested results from workers or humans.

The canonical model carries:

- `summary`
- `contribution_type`
- `authority_level`
- `context_objects`
- `artifacts`
- `execution`
- `events`
- `tool_events`
- `status`

### Context object

Context objects are typed room facts or artifacts.

Built-in policies currently use:

- `belief`
- `note`
- `question`
- `constraint`
- `decision`
- `artifact`

## Relay surface

Local relay endpoint:

- `ws://127.0.0.1:4000/socket/websocket`

Canonical relay flow:

1. worker joins `relay:<workspace_id>`
2. worker sends `relay.hello`
3. worker sends `participant.upsert`
4. server sends `assignment.start`
5. worker sends `contribution.submit`

This relay transports assignments and contributions only. It does not move server authority off the server.

## REST API

Local base API:

- `http://127.0.0.1:4000/api`

### Discovery and runtime

- `GET /api/targets`
- `GET /api/policies`
- `GET /api/policies/:id`

### Rooms

- `POST /api/rooms`
- `GET /api/rooms/:id`
- `POST /api/rooms/:id/run`
- `POST /api/rooms/:id/first_slice`

### History and projections

- `GET /api/rooms/:id/events`
- `GET /api/rooms/:id/timeline`
- `GET /api/rooms/:id/timeline?after=<cursor>`
- `GET /api/rooms/:id/timeline?stream=true`
- `GET /api/rooms/:id/timeline?stream=true&once=true`

### Shared context and manual input

- `GET /api/rooms/:id/context_objects`
- `GET /api/rooms/:id/context_objects/:context_id`
- `POST /api/rooms/:id/contributions`

### Publications

- `GET /api/rooms/:id/publication_plan`
- `GET /api/rooms/:id/publications`
- `POST /api/rooms/:id/publications`

### Connector installation and connection helpers

- `GET /api/connectors/:connector_id/connections`
- `POST /api/connectors/:connector_id/installs`
- `GET /api/connectors/installs/:install_id`
- `POST /api/connectors/installs/:install_id/complete`

## Creating and running rooms

A room is created with:

- a `room_id`
- a `brief`
- a list of `rules`
- a set of participants, usually locked from currently connected targets
- an optional dispatch policy selection

Recommended operator path:

```bash
bin/hive-control
bin/hive-clients
```

Scripted path:

```bash
setup/hive wait-targets --count 2
setup/hive create-room room-manual-1 --participant-count 2
setup/hive run-room room-manual-1 --turn-timeout-ms 180000
```

Hosted test path:

```bash
setup/hive --prod wait-targets --count 2
setup/hive --prod live-demo --participant-count 2
```

## Built-in dispatch policies

Current built-ins:

- `round_robin/v2`
- `resource_pool/v1`
- `human_gate/v1`

### `round_robin/v2`

Runs ordered collaboration phases across the locked participant set.

### `resource_pool/v1`

Chooses the least-used available runtime participant for each assignment.

### `human_gate/v1`

Allows automated runtime work, then blocks on a binding human/manual contribution.

Use `GET /api/policies` when you need the complete policy definitions.

## Manual contributions

Manual contributions are first-class inputs to room state.

Use `POST /api/rooms/:id/contributions` when you want to:

- inject a human decision
- add a reviewer constraint or question
- unblock a `human_gate` room
- record an operator correction

The same contribution model is used for worker and human contributions.

## History and UI surfaces

The server intentionally exposes two history views.

### Raw room events

`GET /api/rooms/:id/events`

Use this when you want the lower-level persisted event stream.

### Room timeline

`GET /api/rooms/:id/timeline`

Use this when you want:

- a UI-friendly activity stream
- incremental polling with `?after=<cursor>`
- server-sent events with `?stream=true`

The timeline is the preferred surface for dashboards and operator UIs.

## Persistence

The server uses SQLite via Ecto.

Persisted tables include:

- room snapshots
- room events
- target registrations
- publication runs

Normal local startup migrates automatically through `bin/server`.

Important migrations live in:

- `priv/repo/migrations/20260326120000_create_jido_hive_persistence.exs`
- `priv/repo/migrations/20260405093000_create_room_events.exs`

## Publications

The server owns publication planning and execution.

Today that includes:

- GitHub issue-style publication drafts and execution
- Notion page-style publication drafts and execution

Useful routes:

- `GET /api/rooms/:id/publication_plan`
- `GET /api/rooms/:id/publications`
- `POST /api/rooms/:id/publications`

The publication plan is derived from accepted room state and available connector targets.

## Development and architecture notes

The server is intentionally layered.

- schema modules define collaboration data primitives
- reducers and command handlers own state transition logic
- policy modules decide assignment order
- persistence and remote execution adapt storage and relay boundaries
- controllers and channels stay thin

Important code areas:

- `lib/jido_hive_server/collaboration`
- `lib/jido_hive_server/persistence.ex`
- `lib/jido_hive_server/remote_exec.ex`
- `lib/jido_hive_server/publications.ex`
- `lib/jido_hive_server_web/controllers`
- `lib/jido_hive_server_web/relay_channel.ex`

## Deployment

Current hosted test base:

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

For the canonical hosted smoke path, see [../README.md#production-smoke-test](../README.md#production-smoke-test).

## Development commands

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
