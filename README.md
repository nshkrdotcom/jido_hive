<p align="center">
  <img src="assets/jido_hive.svg" alt="jido_hive logo" width="200"/>
  <br/>
  <a href="https://github.com/nshkrdotcom/jido_hive">
    <img src="https://img.shields.io/badge/GitHub-nshkrdotcom%2Fjido__hive-1f9cf0?logo=github&logoColor=white" alt="GitHub repository"/>
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-0A8A2A?logo=spdx&logoColor=white" alt="MIT license"/>
  </a>
</p>

# jido_hive

`jido_hive` is a human-first collaborative AI system built as an Elixir monorepo.
It is organized around one strong boundary: the server owns room state and
coordination, while participants, whether human-facing or worker-facing, operate
through explicit contracts instead of side channels.

This repository contains:

- `jido_hive_server`: the authoritative room server, relay, API boundary,
  persistence layer, context graph, and context manager
- `jido_hive_client`: the participant runtime used by long-running workers and
  embedded local tools
- `examples/jido_hive_termui_console`: the first end-user console built on the
  embedded client runtime
- the root workspace project: monorepo tooling, shared quality gates, and
  developer orchestration

If you are new to the repo, read this file first, then move to the package
README that matches the part of the system you are changing.

## Table of contents

- [Why this exists](#why-this-exists)
- [Current system shape](#current-system-shape)
- [Core collaboration model](#core-collaboration-model)
- [Current context reasoning model](#current-context-reasoning-model)
- [Monorepo layout](#monorepo-layout)
- [How a room progresses](#how-a-room-progresses)
- [Local setup](#local-setup)
- [Recommended local workflows](#recommended-local-workflows)
- [Production and deployment](#production-and-deployment)
- [Quality, docs, and developer workflow](#quality-docs-and-developer-workflow)
- [Where to read next](#where-to-read-next)

## Why this exists

Most multi-agent systems start from worker orchestration and then bolt on human
interaction later. `jido_hive` goes the other direction:

- humans and AI participants collaborate inside the same room model
- conversation and durable structured context evolve together
- the room keeps an authoritative event log rather than letting clients invent
  local truth
- context reasoning lives on the server so every client sees the same derived
  relationships, contradictions, and invalidation signals

The result is not a chat app with tools attached. It is a shared collaboration
substrate where structured context objects, dispatch policy, participant scope,
and inspection surfaces all line up around a room snapshot.

## Current system shape

Today the repo delivers three practical surfaces:

### 1. Worker execution plane

Workers connect to the server over Phoenix Channels. They register themselves,
receive assignments, execute locally, and submit structured contributions.

This is the path used by:

- `bin/client-worker`
- `bin/hive-clients`
- the local and production smoke flows

### 2. Operator and human control plane

The server exposes REST endpoints for creating rooms, inspecting room state,
posting contributions, running workflows, and inspecting targets, policies, and
publications.

This is the path used by:

- `setup/hive`
- `bin/hive-control`
- future UI surfaces
- direct manual inspection and debugging

### 3. Embedded human-facing runtime

The client now also ships an embedded Elixir API. That API lets local tools:

- subscribe to room snapshots
- submit human chat text
- convert that text into structured contributions locally
- ground those contributions in a selected existing context object
- refresh timeline and context state
- accept a context object into a binding decision flow

This is the path used by the first `ExRatatui` console example in
`examples/jido_hive_termui_console`.

## Core collaboration model

A room in `jido_hive` is built from five practical primitives:

1. `Room`
   The authoritative coordination container. It owns brief, status,
   participants, events, context, policy progression, and room-local config.
2. `Participant`
   A worker or human contributor known to the room. The room server remains the
   authority even when the participant executes work elsewhere.
3. `Assignment`
   The server's structured request for the next unit of work.
4. `Contribution`
   The participant's structured response. Contributions can contain text,
   metadata, and drafted context objects.
5. `ContextObject`
   A durable knowledge object created from contributions. Current object types
   include values such as `message`, `note`, `belief`, `question`,
   `hypothesis`, `evidence`, `contradiction`, `decision_candidate`, `decision`,
   and `artifact` when emitted as a context object.

The high-level rule is simple:

- the server owns authoritative room state
- clients do not coordinate directly with each other
- derived reasoning is computed from room snapshots, not from client-local caches

## Current context reasoning model

The most important recent shift in the system is that context reasoning is now
server-side and room-local.

`jido_hive_server` derives a context graph from `ContextObject.relations` and
applies a pure context manager over room snapshots. That gives the room a
consistent reasoning layer without adding a graph database, query language, or
another state owner.

### Context graph

The graph model is intentionally narrow:

- node = an existing `ContextObject`
- edge = a normalized relation derived from object relations
- edge types currently include `derives_from`, `references`, `contradicts`,
  `resolves`, `supersedes`, `supports`, and `blocks`
- the graph is rebuilt as pure Elixir maps over room snapshots
- room snapshots expose adjacency and related derived inspection data through the
  server APIs

### Context manager

The context manager is the governance layer that uses the graph. It currently
does four practical things:

- validates append intent against room-owned participant scope
- builds deterministic context views for assignments and human-facing consumers
- emits contradiction-detected room events when new unresolved contradictions
  appear
- marks downstream nodes stale when an appended object supersedes an ancestor

Important implementation rules:

- participant scope is owned by the room under `context_config.participant_scopes`
- reads can extend by one extra `references` hop beyond the participant's base
  scope roots
- updates are append-only through new objects and `supersedes` relations
- stale state is derived and projected, not written back into canonical stored
  context objects

This means the room snapshot now carries richer signals for every consumer:

- context-object detail can include graph adjacency
- context-object listings can include adjacency counts for lightweight clients
- derived stale annotations can be projected inline
- room timelines can surface contradiction and downstream invalidation events

### Prompt-driven graph authoring

The current human path is no longer just "chat that happens to produce some
objects." It now has a stricter graph contract:

- canonical relation names are enforced at append time
- malformed relation names are rejected instead of being silently ignored
- relation-bearing edges must have a non-empty `target_id`
- embedded human tools can submit chat relative to a selected context object
- the TUI exposes explicit relation modes so a human can choose whether a new
  contribution `references`, `derives_from`, `supports`, or `contradicts` the
  selected node

The default human mode is `contextual`, which chooses a relation based on the
generated object type. There is also a `none` mode that submits plain chat
without anchoring the contribution into the graph.

## Monorepo layout

This repository is a root workspace plus three nested Mix projects:

- `mix.exs`
  The workspace root. It uses `blitz_workspace` to fan out repo-wide tasks such
  as compile, test, Credo, Dialyzer, docs, and formatting.
- `jido_hive_server/mix.exs`
  Phoenix API, websocket relay, persistence, room logic, policies, context
  graph, context manager, and deployment integration.
- `jido_hive_client/mix.exs`
  Worker runtime, local executor wrappers, embedded API, interceptor pipeline,
  and local diagnostics surface.
- `examples/jido_hive_termui_console/mix.exs`
  An `ExRatatui` console that proves the embedded human-participation path.

The root workspace matters because quality is enforced across the whole repo, not
just whichever nested app you touched.

## How a room progresses

The easiest way to understand the system is to follow one room from start to
finish.

### 1. Workers register as targets

Workers connect to the websocket relay, send `relay.hello`, upsert their
participant identity, and become available targets for room creation.

### 2. An operator creates a room

The operator or setup script selects the current workers, creates the room, and
optionally locks the room to a fixed participant set and turn budget.

### 3. The server dispatches an assignment

The server examines room state, policy state, and participant availability, then
emits `assignment.start` to the next worker.

### 4. A participant submits a contribution

Workers or embedded human-facing tools submit structured contributions. The
contribution can include drafted context objects with relations to previous
objects.

### 5. The server reduces the contribution

The reducer:

- validates append intent against scope
- materializes context objects
- records the canonical room event
- persists the updated room snapshot
- projects the context graph and annotations
- emits additional derived events when contradictions or invalidation appear

### 6. Room inspection surfaces update

Clients and operators can then poll or stream:

- the canonical event log
- the timeline projection
- the context object listing
- individual context objects with adjacency
- target and policy state

### 7. Policy decides what happens next

The room policy continues dispatching until the room reaches its configured stop
condition.

This same lifecycle supports both worker-driven execution and human-in-the-loop
flows because the server remains the room authority in both cases.

## Local setup

Install and fetch repo prerequisites once from the root:

```bash
bin/setup
```

That prepares the nested Mix apps and the root workspace tooling.

### Local server endpoints

- API: `http://127.0.0.1:4000/api`
- WebSocket: `ws://127.0.0.1:4000/socket/websocket`

### Production endpoints

- API: `https://jido-hive-server-test.app.nsai.online/api`
- WebSocket: `wss://jido-hive-server-test.app.nsai.online/socket/websocket`

## Recommended local workflows

There are three practical ways to work with the repo.

### Fastest worker demo

Use three terminals:

Terminal 1:

```bash
bin/live-demo-server
```

Terminal 2:

```bash
bin/client-worker --worker-index 1
```

Terminal 3:

```bash
bin/client-worker --worker-index 2
```

That exercises the core server relay, worker runtime, room assignment flow, and
structured contribution path.

### Recommended operator flow

Use the menu wrappers:

```bash
bin/hive-control
bin/hive-clients
```

Typical loop:

1. Start a local server with `bin/server` or `bin/live-demo-server`.
2. Launch workers from `bin/hive-clients`.
3. Use `bin/hive-control` to inspect targets, create rooms, run rooms, inspect
   timelines, and examine context state.

This is the best flow for development because it matches how operators will use
the system while still exposing room internals.

### Human-first TUI flow

The first console consumer lives in `examples/jido_hive_termui_console`.

Build the local escript once:

```bash
cd examples/jido_hive_termui_console
mix escript.build
```

Open the lobby:

```bash
./hive console
```

Open a room directly:

```bash
./hive console --room-id room-123
```

Initialize cached connector auth when you need the publish screen:

```bash
./hive auth login github
./hive auth login notion
```

Useful flags:

- `--api-base-url` default: `http://127.0.0.1:4000/api`
- `--participant-id` default: generated human-local identity
- `--participant-role` default: `coordinator`
- `--authority-level` default: `binding`
- `--poll-interval-ms` default: `500`

Current keys:

- lobby: `Enter` open room, `n` wizard, `r` refresh, `d` remove local room id, `q` quit
- room: `Ctrl+B` back to lobby, `Ctrl+E` provenance drill, `Ctrl+A` accept context, `Ctrl+P` publish, `Ctrl+Q` quit
- graph authoring modes: `Ctrl+T` contextual, `Ctrl+F` references, `Ctrl+D` derives_from, `Ctrl+S` supports, `Ctrl+X` contradicts, `Ctrl+V` resolves, `Ctrl+N` plain chat
- publish/conflict/wizard screens: `Esc` backs out of the current screen, `Ctrl+Q` quits globally

The console persists local operator state under `~/.config/hive/`:

- `config.json`: default API URL, participant identity, authority, poll interval
- `rooms.json`: locally saved room ids shown in the lobby
- `credentials.json`: cached connector credentials for publish flows

The example depends on Hex `ex_ratatui` and bootstraps its packaged native
library when launched from the built `./hive` escript.

The room screen remains list-and-pane oriented, but the full console is now a
five-screen operator flow:

- lobby for local room launch and cleanup
- room for conversation, context, event polling, and authoring
- conflict resolution for manual or AI-assisted contradiction handling
- publish for server-driven publication plans and connector bindings
- wizard for room creation from live targets and policies

The context pane surfaces enough graph state to be useful in practice:

- per-object incoming and outgoing edge counts
- stale markers for downstream invalidation
- contradiction markers for conflicting context

## Production and deployment

The current deployment target is the Coolify-managed server instance.

### Important deployment assumption

Commit and push your changes before triggering deployment. The current
`coolify_ex` path resolves the GitHub repository state. It does not deploy your
local uncommitted working tree.

### Deploy from the repo root

```bash
scripts/deploy_coolify.sh
```

The wrapper shells into `jido_hive_server` and runs:

```bash
MIX_ENV=coolify mix coolify.deploy
```

Deployment readiness is anchored to `GET /healthz`, and post-ready verification
checks `/` plus `GET /api/targets`.

Useful follow-up commands:

```bash
cd jido_hive_server
MIX_ENV=coolify mix coolify.latest --project server
MIX_ENV=coolify mix coolify.status --project server --latest
MIX_ENV=coolify mix coolify.app_logs --project server --lines 200 --follow
```

### Production smoke flow

```bash
setup/hive --prod doctor
setup/hive --prod server-info
setup/hive --prod targets
setup/hive --prod live-demo --participant-count 2
```

Useful production wrappers:

```bash
bin/hive-control --prod
bin/hive-clients --prod
```

## Quality, docs, and developer workflow

Run the repo-wide quality gate from the root:

```bash
mix ci
```

That expands to the workspace flow:

1. `mix monorepo.deps.get`
2. `mix monorepo.format --check-formatted`
3. `mix monorepo.compile`
4. `mix monorepo.test`
5. `mix monorepo.credo --strict`
6. `mix monorepo.dialyzer`
7. `mix monorepo.docs`

Useful shortcuts:

```bash
mix mr.deps.get
mix mr.format
mix mr.compile
mix mr.test
mix mr.credo
mix mr.dialyzer
mix mr.docs
```

A few repo norms matter:

- prefer the root workspace commands when touching multiple packages
- treat the server collaboration core as the canonical behavior layer
- keep transport adapters thin
- document changes in the relevant package README when the package surface
  changes materially

## Where to read next

- [jido_hive_server README](jido_hive_server/README.md)
- [jido_hive_client README](jido_hive_client/README.md)
- [jido_hive_termui_console README](examples/jido_hive_termui_console/README.md)
- [setup toolkit README](setup/README.md)

License: MIT
