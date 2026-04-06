# JidoHiveClient

`jido_hive_client` is the local worker runtime for `jido_hive`.

It connects outbound to the server relay, advertises one execution surface, receives assignments, executes them locally, and publishes structured contributions back to the server.

If you are new to the repo, start with the root guide first: [../README.md](../README.md)

## What end users and operators should know

From an operator point of view, a client is a worker node.

A worker:

- connects outbound to the server relay
- advertises a participant and target
- waits for `assignment.start`
- executes locally through `Jido.Harness -> asm`
- returns `contribution.submit`

Workers do not create rooms, choose policies, or own room state. The server does that.

## Quick local start

From the repo root:

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

For the exact hosted production runbook with workers and server log tailing, use:

- [../README.md#production-smoke-test](../README.md#production-smoke-test)

## What the client does

At runtime, the client:

- joins a relay topic over Phoenix channels
- publishes `relay.hello`
- publishes `participant.upsert`
- normalizes incoming `assignment.start` payloads
- builds an execution request from the assignment contract
- executes the assignment locally
- optionally performs a repair pass if the model returns prose instead of strict JSON
- publishes `contribution.submit`
- maintains a local runtime snapshot and event log

## Local control API

The client can expose an optional local control surface intended for:

- local dashboards
- node health views
- assignment history
- SSE event streaming
- manual local execution
- operator debugging

It is not the orchestration authority.

### Routes

When enabled, the local client exposes:

- `GET /api/runtime`
- `GET /api/runtime/assignments`
- `GET /api/runtime/events`
- `GET /api/runtime/events?stream=true`
- `GET /api/runtime/events?stream=true&once=true`
- `POST /api/runtime/assignments/execute`
- `POST /api/runtime/shutdown`

What these routes are for:

- `GET /api/runtime`: current local runtime snapshot
- `GET /api/runtime/assignments`: recent local assignment activity
- `GET /api/runtime/events`: recent local runtime events with cursor support
- `GET /api/runtime/events?stream=true`: SSE event stream for a UI
- `GET /api/runtime/events?stream=true&once=true`: backlog-only SSE response for UI catch-up
- `POST /api/runtime/assignments/execute`: manual local assignment execution hook
- `POST /api/runtime/shutdown`: local process shutdown hook

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
curl http://127.0.0.1:4101/api/runtime/assignments
curl http://127.0.0.1:4101/api/runtime/events
curl -N -H 'Accept: text/event-stream' 'http://127.0.0.1:4101/api/runtime/events?stream=true'
```

## Manual local execution

The manual execution route accepts an assignment-shaped payload.

Typical request body:

```json
{
  "assignment": {
    "assignment_id": "asn-local-1",
    "room_id": "room-local-1",
    "participant_id": "worker-1",
    "participant_role": "analyst",
    "target_id": "target-1",
    "capability_id": "codex.exec.session",
    "phase": "analysis",
    "objective": "Summarize the current room context.",
    "session": {
      "provider": "codex",
      "workspace_root": "/path/to/repo"
    },
    "contribution_contract": {
      "allowed_contribution_types": ["reasoning"],
      "allowed_object_types": ["belief", "note"],
      "allowed_relation_types": ["derives_from", "references"]
    },
    "context_view": {
      "brief": "Build a participation substrate.",
      "context_objects": [],
      "recent_contributions": [],
      "rules": ["Return structured contributions only."],
      "status": "idle"
    }
  }
}
```

## Execution contract

The client expects the assignment contract to carry enough information to execute without fetching mutable room state from somewhere else.

Important assignment fields:

- `assignment_id`
- `room_id`
- `participant_id`
- `participant_role`
- `objective`
- `phase`
- `context_view`
- `contribution_contract`
- `session`

The contribution returned by the client is expected to include:

- `summary`
- `contribution_type`
- `authority_level`
- `context_objects`
- `artifacts`
- `execution`
- `tool_events`
- `events`

## Raw CLI usage

The client is usually started through repo-level wrappers, but the raw CLI is:

```bash
mix run --no-halt -e 'JidoHiveClient.CLI.main(System.argv())' -- \
  --url ws://127.0.0.1:4000/socket/websocket \
  --relay-topic relay:workspace-local \
  --workspace-id workspace-local \
  --user-id user-worker \
  --participant-id worker-1 \
  --participant-role analyst \
  --target-id target-worker-1 \
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

## What developers should know

The client is intentionally split into layers:

- protocol codec for relay contract normalization
- runtime snapshot and event log for local state
- local control router for `REST + SSE`
- executor modules for prompt generation, result decoding, projection, and repair
- relay worker as the lifecycle boundary

That makes the client suitable for:

- local worker UIs
- desktop tooling
- node health and event inspection
- alternate local execution backends

The local API should remain local-first unless explicit authentication and remote exposure requirements are introduced.

## Development

Inside this app:

```bash
mix deps.get
mix test
mix docs --warnings-as-errors
```

Repo-wide from the root:

```bash
mix ci
```
