# JidoHiveClient

`jido_hive_client` is the local worker runtime for `jido_hive`.

It connects outbound to the server relay, advertises a runtime participant and target, receives assignments, executes them locally, and publishes structured contributions back to the server.

Start with the root guide first if you are onboarding: [../README.md](../README.md)

## What this app is for

From an operator point of view, a client is a worker node.

A worker:

- connects outbound to the server relay
- advertises a participant and target
- waits for `assignment.start`
- executes locally through `Jido.Harness -> asm`
- publishes `contribution.submit`
- optionally exposes a local control API for diagnostics or UI work

Workers do not create rooms, choose policies, or own room state. The server does that.

## Quick start

From the repo root:

```bash
bin/client-worker --worker-index 1
```

Start another worker in a second terminal:

```bash
bin/client-worker --worker-index 2
```

These repo wrappers supply the usual runtime defaults for:

- relay URL
- workspace ID
- participant identity
- target identity
- provider selection
- workspace root

For the hosted smoke path, use [../README.md#production-smoke-test](../README.md#production-smoke-test).

## Worker runtime model

The client is designed around a simple boundary.

Input from server:

- `assignment.start`

Output to server:

- `contribution.submit`

Local responsibilities:

- connect to the relay
- normalize the assignment payload
- render prompts from the assignment contract
- execute through `Jido.Harness`
- decode or repair model output into the canonical contribution shape
- publish the contribution
- record local runtime state and events

## Relay behavior

Canonical relay behavior:

1. join `relay:<workspace_id>`
2. push `relay.hello`
3. push `participant.upsert`
4. receive `assignment.start`
5. execute locally
6. push `contribution.submit`

The client is intentionally a relay consumer, not a room orchestrator.

## Assignment contract

The client expects assignments to be self-contained enough to execute without pulling mutable room state from another source.

Important assignment fields:

- `assignment_id`
- `room_id`
- `participant_id`
- `participant_role`
- `phase`
- `objective`
- `context_view`
- `contribution_contract`
- `session`

### `context_view`

The filtered room view typically carries:

- `brief`
- `rules`
- `context_objects`
- `recent_contributions`
- `status`

### `contribution_contract`

The contribution contract constrains what the worker should return.

It typically carries:

- `allowed_contribution_types`
- `allowed_object_types`
- `allowed_relation_types`
- `authority_mode`
- `format`

## Contribution contract

The client returns a normalized contribution map.

Canonical fields include:

- `summary`
- `contribution_type`
- `authority_level`
- `context_objects`
- `artifacts`
- `execution`
- `tool_events`
- `events`
- `status`

The worker runtime now also normalizes common non-canonical model outputs into the canonical contract at the decoder boundary. That includes common wrapped `contribution` responses and legacy object-list variants, so the runtime is more tolerant of realistic model behavior without weakening the server-side contract.

## Local control API

The client can expose an optional local control surface over `REST + SSE`.

This surface is intended for:

- local dashboards
- worker health views
- assignment history
- local event inspection
- manual local execution
- SSE streaming into a UI

It is not the orchestration authority.

### Routes

When enabled, the local API exposes:

- `GET /api/runtime`
- `GET /api/runtime/assignments`
- `GET /api/runtime/events`
- `GET /api/runtime/events?stream=true`
- `GET /api/runtime/events?stream=true&once=true`
- `POST /api/runtime/assignments/execute`
- `POST /api/runtime/shutdown`

### Route purpose

- `GET /api/runtime`: current runtime snapshot
- `GET /api/runtime/assignments`: recent local assignment records
- `GET /api/runtime/events`: recent runtime event backlog
- `GET /api/runtime/events?stream=true`: SSE stream for dashboards
- `GET /api/runtime/events?stream=true&once=true`: one-shot SSE catch-up
- `POST /api/runtime/assignments/execute`: manual local execution of an assignment-shaped payload
- `POST /api/runtime/shutdown`: local process shutdown hook

### Enabling the local API

CLI flags:

- `--control-host`
- `--control-port`

Environment variables:

- `JIDO_HIVE_CLIENT_CONTROL_HOST`
- `JIDO_HIVE_CLIENT_CONTROL_PORT`

Example:

```bash
bin/client-worker --worker-index 1 --control-port 4101
```

Inspect it locally:

```bash
curl http://127.0.0.1:4101/api/runtime
curl http://127.0.0.1:4101/api/runtime/assignments
curl http://127.0.0.1:4101/api/runtime/events
curl -N -H 'Accept: text/event-stream' 'http://127.0.0.1:4101/api/runtime/events?stream=true'
```

## Manual local execution

The manual execution route accepts an assignment-shaped request body.

Example:

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

## Raw CLI usage

The repo-level wrappers are the normal entrypoint, but the raw CLI is:

```bash
mix run --no-halt -e 'JidoHiveClient.CLI.main(System.argv())' -- \
  --url ws://127.0.0.1:4000/socket/websocket \
  --relay-topic relay:workspace-local \
  --workspace-id workspace-local \
  --user-id user-worker \
  --participant-id worker-1 \
  --participant-role worker \
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
- `--control-host`
- `--control-port`

## What the client does internally

The client is split into a few clear layers.

- protocol codec: normalize relay payloads
- runtime state and event log: track local worker history
- control router: expose local `REST + SSE`
- prompt and execution modules: build the run request and execute locally
- result decoder: normalize model output into canonical contributions
- relay worker: own socket lifecycle and assignment handling

This makes the client usable as:

- a plain terminal worker
- a worker with a local dashboard
- a node health endpoint for operator tooling
- a substrate for a richer local UI

## Local-first design constraints

The client local API should remain local-first unless a deliberate authenticated remote exposure design is added.

Current intended use:

- bind locally
- expose to a desktop or browser UI on the same machine
- inspect one worker node at a time

Current non-goals:

- remote orchestration
- server authority duplication
- a second distributed control plane

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
