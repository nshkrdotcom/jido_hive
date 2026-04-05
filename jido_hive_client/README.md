# JidoHiveClient

`jido_hive_client` is the local worker runtime for `jido_hive`.

It connects to the server, advertises one execution target, waits for work, executes turns locally, and sends structured results back to the server.

If you are new to the repo, start with the root guide first: [../README.md](../README.md)

## What end users should know

From an operator point of view, a client is a worker.

A worker:

- connects outbound to the server relay
- announces what it can execute
- waits for `job.start`
- runs the assigned turn locally
- returns `job.result`

Workers do not create rooms or control workflow sequencing. The server does that.

## Quick local start

From the repo root, the most common worker command is:

```bash
bin/client-worker --worker-index 1
```

Start a second worker in another terminal:

```bash
bin/client-worker --worker-index 2
```

These wrappers supply sensible defaults for:

- relay URL
- participant identity
- target identity
- provider selection
- workspace root

For the exact hosted production runbook with two workers and server log tailing, use:

- [../README.md#production-smoke-test](../README.md#production-smoke-test)

## What the client does

At runtime, the client:

- joins a relay topic over Phoenix WebSockets
- registers a target with the server
- normalizes incoming job payloads
- builds the execution request from the collaboration envelope
- executes the turn through `Jido.Harness -> asm`
- performs a repair pass if the model returns prose instead of the required JSON contract
- publishes a structured result back to the server

Structured result data includes:

- status
- summary
- actions
- artifacts
- tool events
- approvals
- execution metadata

## Local control API

The client now includes an optional local control surface intended for:

- local dashboards
- worker health views
- event streaming
- manual job execution
- operator debugging

It is not the orchestration authority.

### Routes

When enabled, the local client exposes:

- `GET /api/runtime`
- `GET /api/runtime/jobs`
- `GET /api/runtime/events`
- `GET /api/runtime/events?stream=true`
- `GET /api/runtime/events?stream=true&once=true`
- `POST /api/runtime/execute`
- `POST /api/runtime/shutdown`

### How to enable it

CLI flags:

- `--control-port`
- `--control-host`

Environment variables:

- `JIDO_HIVE_CLIENT_CONTROL_PORT`
- `JIDO_HIVE_CLIENT_CONTROL_HOST`

Example:

```bash
bin/client-worker --worker-index 1 --control-port 4101
```

Then inspect it locally:

```bash
curl http://127.0.0.1:4101/api/runtime
curl http://127.0.0.1:4101/api/runtime/events
curl -N -H 'Accept: text/event-stream' 'http://127.0.0.1:4101/api/runtime/events?stream=true'
```

## Raw CLI usage

The client is usually started through the repo-level wrappers, but the raw CLI is:

```bash
mix run --no-halt -e 'JidoHiveClient.CLI.main(System.argv())' -- \
  --url ws://127.0.0.1:4000/socket/websocket \
  --relay-topic relay:workspace-local \
  --workspace-id workspace-local \
  --user-id user-architect \
  --participant-id architect \
  --participant-role architect \
  --target-id target-architect \
  --capability-id codex.exec.session \
  --workspace-root /path/to/repo \
  --provider codex \
  --model gpt-5.4 \
  --reasoning-effort low
```

Useful optional flags:

- `--model`
- `--reasoning-effort`
- `--timeout-ms`
- `--cli-path`
- `--control-port`
- `--control-host`

## Execution contract and payload model

The client understands the generalized session/runtime envelope carried by the server.

Important session fields:

- `session.provider`
- `session.execution_surface`
- `session.execution_environment`
- `session.provider_options`

Important defaults still supported:

- `workspace_root`
- provider shorthands from the wrapper scripts

That means older local flows still work, while the underlying wire shape is ready for more generalized execution placement later.

## What developers should know

The client refactor split the worker into clearer pieces:

- relay transport and protocol normalization
- runtime snapshot and event log
- local control API
- executor projection and repair policy modules
- thinner relay worker orchestration

That makes the client a better substrate for:

- local worker UIs
- desktop operator tools
- per-node health inspection
- future alternate execution backends

The local API should remain local-first unless authentication is added.

## Development

Inside this app:

```bash
mix deps.get
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
