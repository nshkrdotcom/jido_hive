# JidoHiveServer

`jido_hive_server` is the authoritative room server for `jido_hive`.

If the repo has one hard rule, it is this one: the server owns room truth.
Workers execute elsewhere. Embedded clients may help humans participate. UIs may
render room state in different ways. None of those surfaces get to define the
room. The server does.

This package contains the authority layer that makes that rule practical:

- room lifecycle and room persistence
- room event reduction into authoritative snapshots
- participant registration and target discovery
- websocket relay for worker execution
- REST APIs for operators and human-facing tools
- dispatch policies and publication planning
- room-local context graph projection
- room-local context manager decisions and derived room events

If you are onboarding to the repo, start with the root [README](../README.md)
and come back here once you need the server-specific details.

## Table of contents

- [What this package is for](#what-this-package-is-for)
- [Responsibilities and non-responsibilities](#responsibilities-and-non-responsibilities)
- [Core server model](#core-server-model)
- [Context graph and context manager](#context-graph-and-context-manager)
- [How the server handles a contribution](#how-the-server-handles-a-contribution)
- [HTTP and websocket surfaces](#http-and-websocket-surfaces)
- [Persistence and projection model](#persistence-and-projection-model)
- [Local development](#local-development)
- [Deployment](#deployment)
- [Code map](#code-map)
- [Related docs](#related-docs)

## What this package is for

`jido_hive_server` is the coordination authority for the whole system.

It exists to answer these questions deterministically:

- what room exists right now?
- who is participating in it?
- what work should happen next?
- what durable context has been contributed so far?
- which contradictions are still unresolved?
- which context is now stale because an ancestor was superseded?
- what should operators or UIs see when they inspect the room?

The server is not a model runner. It is not a local shell executor. It is not a
graph database. It is not a general workflow engine. It is a room-centric
coordination system with explicit projections.

## Responsibilities and non-responsibilities

### Responsibilities

The server is responsible for:

- creating and loading rooms
- receiving canonical room commands through HTTP and relay boundaries
- validating and reducing contributions into room state
- persisting room snapshots and history
- computing room timeline projections
- deriving graph structure from context-object relations
- enforcing participant scope during append validation
- surfacing contradiction and invalidation events
- dispatching assignments according to room policy
- exposing inspection and operator APIs

### Non-responsibilities

The server is intentionally not responsible for:

- executing AI tools or shells itself as the main worker path
- letting clients coordinate directly with each other
- owning a separate graph datastore
- mutating old context objects in place to represent updates
- hiding conflicts by deleting contradiction records

That last point matters. The room prefers explicit historical truth to neatness.

## Core server model

The collaboration core is room-centric.

### Room

A room is the authoritative coordination container. It holds:

- room metadata and brief
- participant registrations
- room status and policy state
- room events and projections
- context objects and context configuration

### Participant

A participant is a worker or human contributor identified by the room.

The room tracks participant identity, capability, and role. The room also owns
context scope under `context_config.participant_scopes`, because scope is a room
governance concern rather than a client-local preference.

### Assignment

Assignments are the server's structured requests for work. Policies decide when
to emit them and who should receive them.

The current built-in room policy surface includes room-centric policies such as:

- `round_robin/v2`
- `resource_pool/v1`
- `human_gate/v1`

### Contribution

A contribution is a participant's structured response. Contributions can contain:

- summary text
- authored-by and provenance metadata
- drafted context objects
- relations between newly appended objects and existing room context

### Context object

The room stores durable context as `ContextObject` values. Current object types
include values such as:

- `message`
- `note`
- `belief`
- `question`
- `hypothesis`
- `evidence`
- `contradiction`
- `decision_candidate`
- `decision`
- `artifact`, when the contribution emits it as a context object

Context objects are append-only. If a participant wants to revise a prior object,
the new object points back with `supersedes`. The old object remains part of room
history.

## Context graph and context manager

The recent context reasoning work lives entirely inside the server and is driven
from room snapshots.

### Context graph

`JidoHiveServer.Collaboration.ContextGraph` derives a room-local graph from
`ContextObject.relations`.

Important properties:

- nodes are existing context objects, not a new persisted entity type
- edges are normalized relation structs
- supported relation types currently include `derives_from`, `references`,
  `contradicts`, `resolves`, `supersedes`, `supports`, and `blocks`
- malformed relation names are rejected during append validation instead of being
  silently projected away
- relation-bearing edges must include a non-empty target id
- graph indexes are built as pure Elixir maps with `outgoing` and `incoming`
  adjacency keyed by `context_id`
- the projection is attached to room snapshots, not persisted as an independent
  source of truth

Core graph queries currently include:

- `adjacency/2`
- `provenance_chain/3`
- `contradictions/1`
- `open_questions/1`
- `derivation_roots/1`
- `neighbors/2`

### Context manager

`JidoHiveServer.Collaboration.ContextManager` is the governance layer that uses
the graph projection.

Its current responsibilities are intentionally narrow:

- `validate_append/3`
  Checks a participant write intent against room-owned scope rules before the
  append is accepted.
- `build_view/3`
  Builds a deterministic, scope-filtered context view from a task context and a
  room snapshot.
- `after_append/3`
  Compares before and after room state to emit contradiction and downstream
  invalidation events plus derived annotations.

Key rules in the current implementation:

- scope lives under `context_config.participant_scopes`
- participant reads start from their writable roots
- `references` sharing allows one additional hop beyond those roots
- unknown relation names fail fast with typed validation errors
- missing or blank relation targets fail fast with typed validation errors
- `supersedes` is append-only and does not mutate previous objects
- stale state is expressed as derived annotations rather than canonical object
  mutation

### Why keep this in the server

This functionality is server-local on purpose. The room owns:

- append acceptance
- scope enforcement
- derived room events
- projection semantics

Extracting the context graph or manager into separate packages before those
contracts settle would create versioning overhead without giving a real
architectural win.

## How the server handles a contribution

The core reduction path looks like this:

1. A participant submits a contribution through the relay or REST boundary.
2. The server normalizes the write intent and resolves the current room snapshot.
3. `ContextManager.validate_append/3` checks object types and relation targets
   against the participant's room-owned scope and rejects malformed relations.
4. The reducer materializes new context objects and appends the canonical room
   event.
5. The snapshot projection rebuilds the context graph and derived annotations.
6. `ContextManager.after_append/3` compares before and after state to emit any
   contradiction-detected or downstream-invalidated events.
7. The room persists the new snapshot and exposes it through events, timeline,
   and context inspection surfaces.

This split matters:

- the canonical room event log records what actually happened
- projections explain the current state in useful operator-facing forms
- derived annotations make downstream effects visible without corrupting the
  append-only historical record

## HTTP and websocket surfaces

The server has two transport categories: REST for operators and human-facing
tools, and Phoenix Channels for live worker execution.

### REST API

The API is mounted under `/api`.

Important route groups:

- connector installation flow
  - `GET /api/connectors/:connector_id/connections`
  - `POST /api/connectors/:connector_id/installs`
  - `GET /api/connectors/installs/:install_id`
  - `POST /api/connectors/installs/:install_id/complete`
- target and policy inspection
  - `GET /api/targets`
  - `GET /api/policies`
  - `GET /api/policies/*id`
- room lifecycle and execution
  - `POST /api/rooms`
  - `GET /api/rooms/:id`
  - `POST /api/rooms/:id/run`
  - `POST /api/rooms/:id/first_slice`
- room inspection
  - `GET /api/rooms/:id/events`
  - `GET /api/rooms/:id/timeline`
  - `GET /api/rooms/:id/context_objects`
  - `GET /api/rooms/:id/context_objects/:context_id`
- contribution append path
  - `POST /api/rooms/:id/contributions`
- publication planning and execution
  - `GET /api/rooms/:id/publication_plan`
  - `GET /api/rooms/:id/publications`
  - `POST /api/rooms/:id/publications`

Practical distinctions:

- `events` is the canonical event log
- `timeline` is the UI-friendly projection
- `context_objects` is the durable context listing
- `context_objects/:context_id` is the best surface for adjacency and object-level
  inspection
- `context_objects` listings now also include adjacency and derived annotations so
  lightweight clients do not need an extra fetch per row

### Phoenix relay

Workers connect to `/socket/websocket`.

Typical execution flow:

1. client opens the websocket
2. client joins the relay topic
3. client sends `relay.hello`
4. client upserts participant identity
5. server dispatches `assignment.start`
6. client submits `contribution.submit`
7. room snapshot and target state advance

The relay is intentionally thin. Room semantics live in the collaboration core,
not in channel callbacks.

## Persistence and projection model

The server uses SQLite through Ecto.

### Canonical persisted concerns

The persisted source of truth is the room state and room history, not a separate
context-graph storage layer.

### Derived concerns

These are rebuilt as projections:

- context graph adjacency
- context annotations such as stale markers
- timeline-friendly renderings of room events

That split keeps persistence simple while still giving operators useful derived
inspection.

### Hydration rule

When a room snapshot is loaded, the server can reattach derived projections from
the canonical stored snapshot. Derived data should be cheap to rebuild from the
persisted room state.

## Local development

Start from the repo root unless you are doing focused server-only work.

### Setup

```bash
bin/setup
```

### Start the server

```bash
bin/server
```

or:

```bash
bin/live-demo-server
```

`bin/server` handles `ecto.create` and `ecto.migrate` before booting Phoenix.

### Local endpoints

- API: `http://127.0.0.1:4000/api`
- WebSocket: `ws://127.0.0.1:4000/socket/websocket`

### Focused server quality gate

```bash
cd jido_hive_server
mix quality
```

### Repo-wide quality gate

```bash
cd ..
mix ci
```

Repo-wide checks are the real gate when the change affects multiple packages or
shared behavior.

## Deployment

The current deployment path is Coolify through `coolify_ex`.

### Important assumption

Commit and push your work first. The Coolify deployment path resolves the GitHub
repository state, not your local uncommitted working tree.

### Deploy

From the repo root:

```bash
scripts/deploy_coolify.sh
```

The wrapper shells into this package and runs:

```bash
MIX_ENV=coolify mix coolify.deploy
```

Useful follow-up commands:

```bash
cd jido_hive_server
MIX_ENV=coolify mix coolify.latest --project server
MIX_ENV=coolify mix coolify.status --project server --latest
MIX_ENV=coolify mix coolify.logs --project server --latest --tail 200
MIX_ENV=coolify mix coolify.app_logs --project server --lines 200 --follow
```

Useful production smoke commands from the repo root:

```bash
setup/hive --prod doctor
setup/hive --prod server-info
setup/hive --prod targets
setup/hive --prod live-demo --participant-count 2
```

## Code map

Important server areas:

- `lib/jido_hive_server/collaboration/`
  Pure room logic, reducers, schemas, policies, context graph, context manager,
  and snapshot projection.
- `lib/jido_hive_server_web/`
  Phoenix controllers, router, websocket boundary, and HTTP normalization.
- `priv/repo/migrations/`
  Ecto migrations.
- `test/jido_hive_server/`
  Server behavior tests, including collaboration and context reasoning coverage.

If you are making behavior changes, prefer changing the collaboration core first
and then adapt the transport boundary to match. That keeps the room model
coherent.

## Related docs

- [Root README](../README.md)
- [Client README](../jido_hive_client/README.md)
- [TermUI example README](../examples/jido_hive_termui_console/README.md)
- [Setup toolkit README](../setup/README.md)
