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

`jido_hive` is a collaborative AI substrate built from two Elixir applications:

- a Phoenix server that owns shared room state, relay dispatch, persistence, and publication execution
- local worker clients that connect outbound, execute assignments, and publish structured contributions back to the server

The default operating model is simple:

1. start the server
2. start one or more workers
3. create a room
4. run the room under a dispatch policy
5. inspect the room timeline or execute publications

## What the system does

Out of the box, `jido_hive` gives you:

- a server-side `REST` control plane
- a Phoenix channel relay for live worker coordination
- room state persisted in SQLite
- explicit collaborative primitives: rooms, participants, assignments, contributions, and context objects
- pluggable dispatch policies
- a UI-friendly room timeline and a lower-level room event log
- local worker execution through `Jido.Harness -> asm`
- optional GitHub and Notion publication execution
- a local worker control surface over `REST + SSE`

This is a coordinator-driven system. The server is authoritative for shared state. Workers are execution nodes, not peer-to-peer agents negotiating directly with each other.

## Repository layout

This repo contains two Mix apps:

- [`jido_hive_server`](jido_hive_server/README.md): Phoenix API, relay, room coordination, persistence, and publications
- [`jido_hive_client`](jido_hive_client/README.md): local worker runtime, relay client, executor wrapper, and local control API

Additional docs:

- [Setup Toolkit](setup/README.md)
- [Architecture Overview](docs/architecture.md)
- [Developer Guide: Multi-Agent Round Robin](docs/developer/multi_agent_round_robin.md)

## Core concepts

### Room

A room is the shared coordination container for one collaborative run.

A room holds:

- the brief
- operating rules
- participants
- assignments
- contributions
- context objects
- dispatch state
- publication state

### Participant

A participant is an actor in the room.

Examples:

- a runtime worker connected over the relay
- a human contributor sending a manual contribution over HTTP

### Dispatch policy

A dispatch policy decides what assignment should be opened next.

Built-in policies:

- `round_robin/v2`
- `resource_pool/v1`
- `human_gate/v1`

### Assignment

An assignment is the unit of work the server sends to a worker.

It includes:

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

A contribution is the structured result a participant sends back.

It includes:

- `summary`
- `contribution_type`
- `authority_level`
- `context_objects`
- `artifacts`
- `execution`
- `tool_events`

### Context object

A context object is a typed unit of shared room knowledge.

Examples:

- `belief`
- `note`
- `question`
- `decision`
- `artifact`

## Fastest local onboarding

From a fresh clone:

```bash
git clone <repo>
cd jido_hive
bin/setup
```

Open three terminals.

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

What you should see:

- the server starts and applies pending migrations
- both workers connect and register participants/targets
- the live demo creates a room and runs it
- workers receive `assignment.start` and publish `contribution.submit`
- the server timeline and room state advance as contributions arrive

## Recommended operator flow

Use the menu-driven tools:

Terminal 1:

```bash
bin/hive-control
```

Terminal 2:

```bash
bin/hive-clients
```

Typical loop:

1. in `bin/hive-clients`, start two or more workers
2. in `bin/hive-control`, create and run a room
3. inspect targets, room state, timeline, and publications from the control tool

Production equivalents:

```bash
bin/hive-control --prod
bin/hive-clients --prod
```

## Server surfaces

The server exposes:

- `REST` at `/api`
- Phoenix WebSockets at `/socket/websocket`

Key `REST` endpoints:

- `GET /api/targets`
- `GET /api/policies`
- `GET /api/policies/*id`
- `POST /api/rooms`
- `GET /api/rooms/:id`
- `GET /api/rooms/:id/events`
- `GET /api/rooms/:id/timeline`
- `GET /api/rooms/:id/timeline?after=<cursor>`
- `GET /api/rooms/:id/timeline?stream=true`
- `GET /api/rooms/:id/context_objects`
- `GET /api/rooms/:id/context_objects/:context_id`
- `POST /api/rooms/:id/contributions`
- `POST /api/rooms/:id/run`
- `GET /api/rooms/:id/publication_plan`
- `GET /api/rooms/:id/publications`
- `POST /api/rooms/:id/publications`

Relay events:

- client to server: `relay.hello`
- client to server: `participant.upsert`
- server to client: `assignment.start`
- client to server: `contribution.submit`

See [`jido_hive_server/README.md`](jido_hive_server/README.md) for the server-oriented guide.

## Client surfaces

When enabled, each worker can expose a local control API.

Routes:

- `GET /api/runtime`
- `GET /api/runtime/assignments`
- `GET /api/runtime/events`
- `GET /api/runtime/events?stream=true`
- `GET /api/runtime/events?stream=true&once=true`
- `POST /api/runtime/assignments/execute`
- `POST /api/runtime/shutdown`

That surface is for diagnostics, local UI work, and manual local execution. It is not the system orchestration authority.

See [`jido_hive_client/README.md`](jido_hive_client/README.md) for the worker-oriented guide.

## Useful local commands

Repo-level commands:

```bash
bin/setup
bin/server
bin/live-demo-server
bin/hive-control
bin/hive-clients
bin/client-worker --worker-index 1
setup/hive help
```

Useful manual control:

```bash
setup/hive wait-server
setup/hive wait-targets --count 2
setup/hive create-room room-manual-1 --participant-count 2
setup/hive run-room room-manual-1 --turn-timeout-ms 180000
setup/hive publication-plan room-manual-1
setup/hive publication-runs room-manual-1
```

## Production endpoints

Current deployed server:

- HTTPS: `https://jido-hive-server-test.app.nsai.online`
- API base: `https://jido-hive-server-test.app.nsai.online/api`
- WebSocket relay: `wss://jido-hive-server-test.app.nsai.online/socket/websocket`

Useful production checks:

```bash
setup/hive --prod doctor
setup/hive --prod targets
setup/hive --prod server-info
```

## Production smoke test

1. Tail prod server logs:

```bash
cd /home/home/p/g/n/jido_hive/jido_hive_server
MIX_ENV=coolify mix coolify.app_logs --project server --lines 200 --follow
```

2. Run prod worker 1:

```bash
cd /home/home/p/g/n/jido_hive
bin/client-worker --prod --worker-index 1
```

3. Run prod worker 2:

```bash
cd /home/home/p/g/n/jido_hive
bin/client-worker --prod --worker-index 2
```

4. Wait for both workers:

```bash
cd /home/home/p/g/n/jido_hive
setup/hive --prod wait-targets --count 2
```

5. Run the prod flow:

```bash
cd /home/home/p/g/n/jido_hive
setup/hive --prod live-demo --participant-count 2
```

## Development and quality

Repo-wide quality gate:

```bash
mix ci
```

Useful monorepo tasks:

```bash
mix monorepo.format
mix monorepo.compile
mix monorepo.test
mix monorepo.credo
mix monorepo.dialyzer
mix monorepo.docs
```

## Architecture summary

The design follows a functional-core-first approach:

- data structures define the collaboration model
- reducers and policy modules make decisions in pure code
- controllers and channels stay thin
- OTP processes wrap lifecycle, persistence, transport, and worker supervision

If you are extending the system, the main rule is simple:

- keep shared state and orchestration on the server
- keep execution local to the worker
- exchange typed assignments and contributions over explicit contracts
