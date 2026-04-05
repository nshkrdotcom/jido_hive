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

`jido_hive` is a collaborative AI runtime made of:

- a Phoenix server that coordinates rooms, workers, workflows, and publications
- local Elixir clients that connect outbound, execute turns, and report results
- a shell toolkit for operators who want to run demos, inspect state, and publish outputs

The default experience is: start the server, start one or more workers, create a room, and let the server orchestrate a structured multi-turn workflow across those workers.

## Who this is for

- end users and operators who want to run local or hosted collaborative AI workflows
- developers who want a generalized substrate for orchestration, local execution, and UI integration
- integrators who want a server-controlled collaboration system with pluggable workflows and local worker surfaces

## What the system does

Out of the box, `jido_hive` gives you:

- a server-side control plane over `REST`
- a live worker relay over Phoenix WebSockets
- durable room persistence in SQLite
- workflow-aware room execution
- local worker execution through `Jido.Harness -> asm`
- optional GitHub and Notion publication flows
- a local client control surface over `REST + SSE` for worker visibility and UI work

The system is coordinator-driven. Workers do not negotiate among themselves. The server owns room state, workflow sequencing, dispatch, result intake, and publication planning.

## Repository layout

This repo contains two Mix apps:

- [`jido_hive_server`](jido_hive_server/README.md): Phoenix API, relay, workflow orchestration, persistence, and publication execution
- [`jido_hive_client`](jido_hive_client/README.md): local worker runtime, relay client, execution wrapper, and local control API

Additional user-facing docs:

- [Setup Toolkit](setup/README.md)
- [Architecture Overview](docs/architecture.md)
- [Developer Guide: Multi-Agent Round Robin](docs/developer/multi_agent_round_robin.md)

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

- the server starts locally and applies any pending migrations
- both workers connect and register targets
- the live demo creates a room and runs a workflow
- workers print execution logs as they receive `job.start` and publish `job.result`

## Recommended operator flow

For the main user flow, use the two menu-driven tools:

Terminal 1:

```bash
bin/hive-control
```

Terminal 2:

```bash
bin/hive-clients
```

Typical loop:

1. In `bin/hive-clients`, start `2` workers or choose a custom worker count.
2. In `bin/hive-control`, create and run a room.
3. Watch worker output for prompt previews, execution status, and result publication.

Production equivalents:

```bash
bin/hive-control --prod
bin/hive-clients --prod
```

## Core concepts

### Server

The server owns:

- room creation and execution
- workflow definitions and workflow selection
- live relay topics and worker dispatch
- result intake and state reduction
- durable snapshots and event history
- publication planning and execution

See the server app guide: [`jido_hive_server/README.md`](jido_hive_server/README.md)

### Client

Each client:

- connects outbound to the server relay
- registers one execution target
- waits for work
- executes turns locally
- returns structured results
- optionally exposes a local control API for status, events, and manual execution

See the client app guide: [`jido_hive_client/README.md`](jido_hive_client/README.md)

### Rooms and workflows

A room is the unit of collaborative execution.

A workflow defines the ordered phases that run inside that room. The default workflow is a round-robin proposal, critique, and resolution flow. The generalized substrate also supports additional workflow definitions such as chain-of-responsibility.

### Targets and workers

A worker advertises a target to the server. The server dispatches room turns to registered targets over the WebSocket relay.

### Publications

After a room completes, the server can prepare and execute publication steps such as GitHub and Notion writes through configured connector flows.

## What is exposed

### Server surfaces

The server exposes:

- `REST` API at `/api`
- Phoenix WebSocket relay at `/socket/websocket`

Key server APIs include:

- `GET /api/targets`
- `GET /api/workflows`
- `POST /api/rooms`
- `GET /api/rooms/:id`
- `GET /api/rooms/:id/events`
- `GET /api/rooms/:id/timeline`
- `POST /api/rooms/:id/run`
- `GET /api/rooms/:id/publication_plan`
- `POST /api/rooms/:id/publications`

### Client surfaces

The client exposes, when enabled, a local control API:

- `GET /api/runtime`
- `GET /api/runtime/jobs`
- `GET /api/runtime/events`
- `GET /api/runtime/events?stream=true`
- `POST /api/runtime/execute`
- `POST /api/runtime/shutdown`

That local surface is intended for diagnostics, local UIs, and operator tooling. It is not the orchestration authority.

## Common local commands

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

Useful manual room control:

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

Typical production usage:

```bash
bin/hive-clients --prod
bin/hive-control --prod
```

Or explicitly:

```bash
bin/client-worker --prod --worker-index 1
bin/client-worker --prod --worker-index 2
setup/hive --prod live-demo --participant-count 2
```

Useful checks:

```bash
setup/hive --prod doctor
setup/hive --prod targets
setup/hive --prod server-info
```

## Production smoke test

Use this exact sequence when you want to confirm that the hosted production system is working end to end.

1. Tail production server logs:

```bash
cd /home/home/p/g/n/jido_hive/jido_hive_server
MIX_ENV=coolify mix coolify.app_logs --project server --lines 200 --follow
```

2. Start production worker 1:

```bash
cd /home/home/p/g/n/jido_hive
bin/client-worker --prod --worker-index 1
```

3. Start production worker 2:

```bash
cd /home/home/p/g/n/jido_hive
bin/client-worker --prod --worker-index 2
```

4. Wait for both workers to register:

```bash
cd /home/home/p/g/n/jido_hive
setup/hive --prod wait-targets --count 2
```

5. Run the production flow:

```bash
cd /home/home/p/g/n/jido_hive
setup/hive --prod live-demo --participant-count 2
```

Expected result:

- the two workers connect and register targets
- the server logs show relay activity and room execution
- the live demo creates a room, runs the workflow, and prints the resulting room state
- if production is unhealthy, this is the first runbook to use before deeper debugging

## Publishing to GitHub and Notion

The setup toolkit wraps connector installation and publication execution.

Examples:

```bash
setup/hive start-install github --subject octocat --scope repo
setup/hive complete-install <install-id> --subject octocat --scope repo
setup/hive start-install notion --subject notion-workspace
setup/hive complete-install <install-id> --subject notion-workspace
```

List live connections:

```bash
setup/hive connections github
setup/hive connections notion
```

Execute publications:

```bash
setup/hive publish room-manual-1 \
  --github-connection connection-github-1 \
  --github-repo owner/repo \
  --notion-connection connection-notion-1 \
  --notion-data-source-id data-source-id \
  --notion-title-property Name
```

## Persistence and migrations

The server uses SQLite through Ecto for durable state.

Main persisted data:

- room snapshots
- room events
- target registrations
- publication runs

Local server startup applies migrations automatically through the repo-level `bin/server` wrapper.

## Architecture notes for developers

The current generalized substrate is organized around:

- server control plane over `REST`
- live dispatch plane over Phoenix channels
- server internals modeled as `commands -> events -> snapshot`
- workflow registry and workflow-specific execution logic
- client runtime state and event log
- client local `REST + SSE` surface for node-local introspection

That split is deliberate:

- shared multi-user state belongs on the server
- local worker state belongs on the client

If you are building a UI, prefer:

- server `REST` for shared rooms, workflows, targets, publications, and room timelines
- client `REST + SSE` for local worker runtime state, event streams, and manual execution

## Deployment

Deployments use `coolify_ex` from inside `jido_hive_server`.

From the repo root:

```bash
export COOLIFY_BASE_URL="https://coolify.example.com"
export COOLIFY_TOKEN="..."
export COOLIFY_APP_UUID="..."
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

## Development and quality

From the repo root:

```bash
mix ci
```

That runs the repo-wide quality flow:

1. `mix deps.get`
2. `mix format --check-formatted`
3. `mix compile`
4. `mix test`
5. `mix credo --strict`
6. `mix dialyzer`
7. `mix docs`

Useful monorepo shortcuts:

```bash
mix mr.deps.get
mix mr.format
mix mr.compile
mix mr.test
mix mr.credo
mix mr.dialyzer
mix mr.docs
```

## Where to go next

- Want to operate the system: read [setup/README.md](setup/README.md)
- Want to understand the server: read [`jido_hive_server/README.md`](jido_hive_server/README.md)
- Want to understand the worker/client side: read [`jido_hive_client/README.md`](jido_hive_client/README.md)
- Want architecture and deeper developer context: read [docs/architecture.md](docs/architecture.md)
