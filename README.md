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

`jido_hive` is a human-first collaborative AI substrate built as two Elixir applications:

- [`jido_hive_server`](jido_hive_server/README.md): the room authority, relay, API, persistence layer, and policy runner
- [`jido_hive_client`](jido_hive_client/README.md): the participant runtime used by worker CLIs, embedded local tooling, and the first TUI example

The current system is designed around one idea: humans and AI participants should collaborate in a shared room where conversation and structured context evolve together.

## What the system does today

A room in `jido_hive` has five practical primitives:

1. `Room`: the authoritative coordination container
2. `Participant`: a worker or human contributor
3. `Assignment`: scoped work sent to a participant
4. `Contribution`: structured output returned to the room
5. `ContextObject`: durable knowledge objects such as `belief`, `note`, `question`, `hypothesis`, `evidence`, `contradiction`, `decision_candidate`, and `decision`

The server owns room state and dispatch policy. Clients never coordinate directly with each other.

## Current collaboration surfaces

### 1. Worker execution plane

AI workers connect over Phoenix WebSockets and receive `assignment.start` packets. They answer with `contribution.submit` payloads.

This is the path used by:
- `bin/client-worker`
- `bin/hive-clients`
- the production smoke flow

### 2. Human and operator control plane

The server exposes REST APIs for room creation, room inspection, manual contributions, timelines, and policy/workflow inspection.

This is the path used by:
- `setup/hive`
- `bin/hive-control`
- future web and API operators

### 3. Embedded client runtime

`jido_hive_client` now also exposes a direct Elixir embedding API for local tools:
- start an embedded participant runtime
- submit human chat text
- intercept that text locally into structured contributions
- refresh and inspect room snapshots
- accept a context object into a binding decision

This is the path used by the first TUI example.

### 4. TUI example

The repo now includes:
- `examples/jido_hive_termui_console`

It is a `term_ui` application with:
- left pane: conversation timeline
- right pane: structured context view
- bottom input: plain chat entry

The TUI talks to `jido_hive_client` programmatically in Elixir. It does not shell out to a separate HTTP client process.

## Repo layout

- `jido_hive_server/`: Phoenix server, REST API, relay, persistence, policies
- `jido_hive_client/`: worker runtime, embedded runtime, interceptor, local control API
- `examples/jido_hive_termui_console/`: first interactive terminal UI consumer
- `setup/hive`: operator and demo orchestration script
- `bin/`: server, worker, and operator wrappers

## Fastest local setup

```bash
bin/setup
```

## Fastest worker demo

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

That proves the server relay, worker runtime, assignment flow, structured contributions, and room progression.

## Recommended operator flow

Use the menu wrappers:

```bash
bin/hive-control
bin/hive-clients
```

Typical flow:

1. Start workers in `bin/hive-clients`
2. Create or run rooms from `bin/hive-control`
3. Inspect targets, room timelines, context objects, and publication state

Production equivalents:

```bash
bin/hive-control --prod
bin/hive-clients --prod
```

## Human-first local flow with the TUI

The first TUI consumer lives at:
- `examples/jido_hive_termui_console`

The TUI depends on the local `term_ui` source tree and examples at:
- `/home/home/p/g/n/term_ui`

To run the TUI against an existing room:

```bash
cd examples/jido_hive_termui_console
mix run -- --room-id room-123 --participant-id alice
```

Useful flags:
- `--api-base-url` default: `http://127.0.0.1:4000/api`
- `--participant-role` default: `collaborator`
- `--poll-interval-ms` default: `500`

TUI keys:
- `Enter`: submit chat
- `Up/Down`: move selected context object
- `Ctrl+A`: accept the selected context object into a binding decision
- `Ctrl+R`: refresh immediately
- `Ctrl+Q`: quit

## Transports and APIs

### Server

- Local API: `http://127.0.0.1:4000/api`
- Local WebSocket: `ws://127.0.0.1:4000/socket/websocket`
- Production API: `https://jido-hive-server-test.app.nsai.online/api`
- Production WebSocket: `wss://jido-hive-server-test.app.nsai.online/socket/websocket`

### Client local control API

A worker can expose a local inspection surface with `--control-port`.

Example:

```bash
bin/client-worker --worker-index 1 --control-port 4101
```

Useful local routes:
- `GET /api/runtime`
- `GET /api/runtime/assignments`
- `GET /api/runtime/events`
- `GET /api/runtime/events?stream=true`
- `POST /api/runtime/assignments/execute`

## Production smoke test

1. Tail prod server logs:

```bash
cd jido_hive_server
MIX_ENV=coolify mix coolify.app_logs --project server --lines 200 --follow
```

2. Start prod workers:

```bash
cd /home/home/p/g/n/jido_hive
bin/client-worker --prod --worker-index 1
bin/client-worker --prod --worker-index 2
```

3. Wait for target registration:

```bash
setup/hive --prod wait-targets --count 2
```

4. Run the production flow:

```bash
setup/hive --prod live-demo --participant-count 2
```

## Quality and development

Repo-wide quality gate:

```bash
mix ci
```

Useful workspace commands:

```bash
mix monorepo.deps.get
mix monorepo.format
mix monorepo.compile
mix monorepo.test
mix monorepo.credo
mix monorepo.dialyzer
mix monorepo.docs
```

## Read next

- [Server README](jido_hive_server/README.md)
- [Client README](jido_hive_client/README.md)
- [TUI example README](examples/jido_hive_termui_console/README.md)

License: MIT
