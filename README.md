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

`jido_hive` is a collaborative AI runtime built from two Elixir applications:

- `jido_hive_server`: a Phoenix control plane and relay that owns shared room state, policy dispatch, persistence, and publication execution
- `jido_hive_client`: a local worker runtime that connects outbound, executes assignments, and sends structured contributions back to the server

The system is coordinator-driven.

- the server is authoritative for room state
- workers are execution nodes, not peer-to-peer coordinators
- collaboration happens through explicit room primitives instead of ad hoc chat state

## What you can do with it

Out of the box, `jido_hive` gives you:

- room-based multi-worker collaboration
- structured assignment dispatch over Phoenix channels
- structured contributions with typed context objects and artifacts
- pluggable dispatch policies
- room state persistence in SQLite
- room event logs and a UI-friendly timeline
- local worker control APIs over `REST + SSE`
- publication planning and execution for GitHub and Notion
- operator tooling for local and hosted runs

Typical lifecycle:

1. start the server
2. start one or more workers
3. create a room with a brief, rules, and participants
4. run the room under a dispatch policy
5. inspect room state, timeline, and publication plan
6. optionally publish the result

## Core model

### Room

A room is the shared coordination container for a collaboration run.

A room contains:

- `room_id`
- `brief`
- `rules`
- `participants`
- `assignments`
- `contributions`
- `context_objects`
- `dispatch_policy_id`
- `dispatch_state`
- publication state

### Participant

A participant is an actor in the room.

Examples:

- a runtime worker connected over the relay
- a human reviewer submitting a manual contribution over HTTP

### Assignment

An assignment is the server-issued work packet sent to one participant.

Assignments include:

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

A contribution is the structured result returned by a participant.

Contributions include:

- `summary`
- `contribution_type`
- `authority_level`
- `context_objects`
- `artifacts`
- `execution`
- `tool_events`
- `events`
- `status`

### Context object

A context object is a typed unit of room knowledge.

Common types in the built-in policies:

- `belief`
- `note`
- `question`
- `constraint`
- `decision`
- `artifact`

### Dispatch policy

A dispatch policy determines which assignments should be opened and in what order.

Built-in policies:

- `round_robin/v2`
- `resource_pool/v1`
- `human_gate/v1`

## Repository layout

This repo contains two Mix apps:

- [jido_hive_server/README.md](jido_hive_server/README.md)
- [jido_hive_client/README.md](jido_hive_client/README.md)

Additional docs:

- [setup/README.md](setup/README.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/developer/multi_agent_round_robin.md](docs/developer/multi_agent_round_robin.md)

## Fast local onboarding

From a fresh clone:

```bash
git clone <repo>
cd jido_hive
bin/setup
```

### Fastest demo path

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

What this does:

- starts the server
- applies local migrations
- starts two workers
- creates a room
- runs the room under the default policy
- prints the room result and publication plan

### Recommended operator path

Use the menu wrappers.

Terminal 1:

```bash
bin/hive-control
```

Terminal 2:

```bash
bin/hive-clients
```

Typical local operator flow:

1. start workers from `bin/hive-clients`
2. inspect targets from `bin/hive-control`
3. create a room
4. run the room
5. inspect the room timeline
6. inspect or execute publications

## Local endpoints

Server:

- API: `http://127.0.0.1:4000/api`
- WebSocket: `ws://127.0.0.1:4000/socket/websocket`

Hosted test deployment:

- API: `https://jido-hive-server-test.app.nsai.online/api`
- WebSocket: `wss://jido-hive-server-test.app.nsai.online/socket/websocket`

## Server API summary

Important server routes:

- `GET /api/targets`
- `GET /api/policies`
- `GET /api/policies/:id`
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

Relay events:

- client to server: `relay.hello`
- client to server: `participant.upsert`
- server to client: `assignment.start`
- client to server: `contribution.submit`

See [jido_hive_server/README.md](jido_hive_server/README.md) for the server guide.

## Client API summary

Workers can expose a local control surface.

Routes:

- `GET /api/runtime`
- `GET /api/runtime/assignments`
- `GET /api/runtime/events`
- `GET /api/runtime/events?stream=true`
- `GET /api/runtime/events?stream=true&once=true`
- `POST /api/runtime/assignments/execute`
- `POST /api/runtime/shutdown`

That surface is for local UI, diagnostics, and manual local execution. It does not replace the server control plane.

See [jido_hive_client/README.md](jido_hive_client/README.md) for the worker guide.

## Useful commands

Setup and local runtime:

```bash
bin/setup
bin/server
bin/live-demo-server
bin/client-worker --worker-index 1
bin/client-worker --worker-index 2
```

Operator wrappers:

```bash
bin/hive-control
bin/hive-clients
```

Setup toolkit:

```bash
setup/hive help
setup/hive wait-server
setup/hive wait-targets --count 2
setup/hive targets
setup/hive create-room room-manual-1 --participant-count 2
setup/hive run-room room-manual-1 --turn-timeout-ms 180000
setup/hive publication-plan room-manual-1
setup/hive publication-runs room-manual-1
```

Quality:

```bash
mix ci
mix monorepo.format
```

## Production smoke test

This is the canonical hosted smoke path.

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

Expected outcome:

- the room is created successfully
- assignments dispatch to both workers
- both workers publish structured contributions
- the room reaches `publication_ready`
- the publication plan is generated

## Deployment

Deployments use `coolify_ex` from the server app.

From the repo root:

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

## Architecture notes for developers

The implementation is layered in the Elixir/OTP style.

- data: participants, assignments, contributions, context objects, room state
- functions: reducers, codecs, policy selection, projections
- boundaries: controllers, channels, persistence, external integrations
- lifecycle: room servers, relay workers, application supervision
- workers: local client runtimes and server-side dispatch boundaries

The important architectural constraint is simple:

- the server owns coordination state
- the client owns execution
- transports stay thin
- structured contracts sit at the boundary

## README map

For more detail:

- root system overview: [README.md](README.md)
- server details and API: [jido_hive_server/README.md](jido_hive_server/README.md)
- client runtime and local API: [jido_hive_client/README.md](jido_hive_client/README.md)
- setup toolkit: [setup/README.md](setup/README.md)
