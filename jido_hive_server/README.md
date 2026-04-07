# JidoHiveServer

`jido_hive_server` is the authoritative room server for `jido_hive`.

It owns:
- room lifecycle and persistence
- dispatch policy execution
- participant registration and relay presence
- room event reduction into authoritative state
- room-local context graph projection
- room-local context manager decisions and derived events
- HTTP APIs for operators and human participants
- Phoenix channel transport for worker execution

If you are onboarding, start with the repo root [README](../README.md).

## What the server is responsible for

The server is the source of truth for collaborative state. It accepts contributions, validates them, reduces them into room state, persists the result, and decides what assignment should happen next.

It also now derives:
- normalized graph edges from `ContextObject.relations`
- participant-specific context views from room snapshots
- contradiction and downstream-invalidation room events
- stale annotations without mutating canonical stored context objects

The server does not execute AI models itself. It coordinates participants that do.

## Main concepts

### Room

A room is the shared coordination container. It holds:
- the room brief and status
- participant registrations
- room events
- accumulated context objects
- current dispatch state

### Dispatch policy

Policies decide what happens next from the current room state. The built-in system is intentionally narrow and room-centric rather than workflow-framework heavy.

Current built-in policy surface includes room policies such as:
- `round_robin/v2`
- `resource_pool/v1`
- `human_gate/v1`

### Contribution and context

Participants submit structured contributions. The reducer extracts context objects such as:
- `belief`
- `note`
- `question`
- `hypothesis`
- `evidence`
- `contradiction`
- `decision_candidate`
- `decision`

The server stores provenance and room history so the current context can be inspected later through API projections.

Current context inspection now includes:
- graph adjacency on context-object detail
- derived stale flags inline on affected objects
- timeline entries for contradiction detection and downstream invalidation

## Server transports

### REST API

REST is the operator and UI control plane.

Common routes include:
- `POST /api/rooms`
- `POST /api/rooms/:id/run`
- `GET /api/rooms/:id/events`
- `GET /api/rooms/:id/timeline`
- `GET /api/rooms/:id/context_objects`
- `POST /api/rooms/:id/contributions`
- `GET /api/policies`
- `GET /api/workflows`
- `GET /api/targets`

Important notes:
- `timeline` is the UI-friendly projection
- `events` is the canonical event log
- `timeline` supports cursor polling and SSE variants used by local tools and future UIs

### Phoenix relay

Phoenix Channels carry the live worker execution plane.

Typical flow:
1. client connects to `/socket/websocket`
2. client joins a relay topic
3. client sends `relay.hello`
4. client sends `participant.upsert`
5. server sends `assignment.start`
6. client sends `contribution.submit`

## Local development

Start the server from repo root:

```bash
bin/server
```

Or use the demo wrapper:

```bash
bin/live-demo-server
```

Local endpoints:
- API: `http://127.0.0.1:4000/api`
- WebSocket: `ws://127.0.0.1:4000/socket/websocket`

`bin/server` runs `ecto.create` and `ecto.migrate` before starting Phoenix.

## Human participation path

Humans can participate through the same room model without impersonating a worker daemon.

Today that path exists in two practical forms:
- direct server REST contributions to `POST /api/rooms/:id/contributions`
- the embedded client runtime used by `examples/jido_hive_termui_console`, which converts human chat text into structured contributions before posting them to the server

## Persistence and migrations

The server uses SQLite via Ecto.

Migrations live under:
- `priv/repo/migrations`

Local migration path:

```bash
cd jido_hive_server
mix ecto.create
mix ecto.migrate
```

## Production deployment

The current deployment target is:
- `https://jido-hive-server-test.app.nsai.online`

Deploy from repo root:

```bash
scripts/deploy_coolify.sh
```

Tail deployment logs:

```bash
cd jido_hive_server
MIX_ENV=coolify mix coolify.app_logs --project server --lines 200 --follow
```

## Architecture notes for developers

The code is split on purpose:
- `lib/jido_hive_server/collaboration/`: pure room logic, reducers, schemas, policies, projections
- `lib/jido_hive_server_web/`: Phoenix controllers, channel boundary, HTTP normalization
- OTP processes wrap the pure core and persistence boundaries

The design rule is simple:
- keep room logic in the collaboration core
- keep transport and persistence concerns at the boundary
- treat the relay and controllers as thin adapters

## Related docs

- [Repo README](../README.md)
- [Client README](../jido_hive_client/README.md)
- [TUI example README](../examples/jido_hive_termui_console/README.md)
