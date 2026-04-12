# Jido Hive Debugging Guide

This is the default debugging order for `jido_hive`.

Use it when:

- a room looks stale
- a mutation appears to hang
- a worker is not registering
- a run operation is blocked
- the TUI shows something that looks wrong
- the web UI shows something that looks wrong

The governing rule is:

1. server truth first
2. headless operator client second
3. shared operator surface third
4. worker runtime fourth if the bug involves targets, room channels, or assignment execution
5. TUI or web UI last

If a behavior reproduces from the headless client or shared surface, it is not a
UI-only bug.

## Current transport split

Today the system uses two transport styles:

- operator surfaces use the HTTP API
- workers use websocket room channels

That means:

- `setup/hive` is an HTTP-oriented operator/tooling surface
- `jido_hive_client room ...` commands are HTTP-backed
- `jido_hive_surface` is the shared UI-neutral workflow layer over those
  operator seams
- the Switchyard-backed console is HTTP-backed for room inspection and human
  actions
- `jido_hive_web` is HTTP-backed for room inspection and human actions
- `bin/client` and `bin/client-worker` launch websocket room workers through
  `jido_hive_worker_runtime`

## What each layer owns

- `jido_hive_server`
  authoritative room truth, room-event truth, reduction, publications, connector
  state
- `jido_hive_client`
  reusable operator workflows, room-scoped local session behavior, headless CLI
- `jido_hive_surface`
  shared room and publication workflows for TUI and web packages
- `jido_hive_worker_runtime`
  relay worker registration, assignment delivery, local execution, worker-local
  runtime state
- `jido_hive_switchyard_tui`, `jido_hive_web`, and `examples/jido_hive_console`
  presentation, routing, local screen state, and key handling

## Standard triage sequence

Use one bug, one room, one sequence.

### 1. Confirm server truth

Start here before touching the client or TUI.

```bash
setup/hive server-info
curl -sS http://127.0.0.1:4000/api/rooms/<room-id> | jq
curl -sS http://127.0.0.1:4000/api/rooms/<room-id>/events | jq
```

Questions this answers:

- does the server think the room is `idle`, `running`, `blocked`, or
  `publication_ready`?
- does the room already contain the contribution or context object you expect?
- is the room event feed moving even if the console looks stale?

If server truth is wrong, stop blaming the client, surface, or UI.

### 2. Reproduce through `jido_hive_client`

This is the main seam test.

```bash
cd jido_hive_client
mix escript.build

./jido_hive_client room show \
  --api-base-url http://127.0.0.1:4000/api \
  --room-id <room-id> | jq

./jido_hive_client room workflow \
  --api-base-url http://127.0.0.1:4000/api \
  --room-id <room-id> | jq

./jido_hive_client room tail \
  --api-base-url http://127.0.0.1:4000/api \
  --room-id <room-id> | jq
```

Questions this answers:

- can the client see the same truth as raw HTTP?
- is the bug already present before the TUI is involved?
- is the issue in operator/session semantics rather than rendering?

### 3. Reproduce through the shared surface or human action headlessly

Use the shared surface next when the issue seems UI-adjacent but should still be
reproducible without Phoenix or terminal state.

Typical examples:

- room list does not match saved rooms
- publication workspace looks wrong
- provenance flow or room create/run validation looks inconsistent

Then use the headless client with trace for submit, accept, resolve, or publish
bugs.

Use this for submit, accept, resolve, or publish bugs.

```bash
JIDO_HIVE_CLIENT_LOG_LEVEL=debug \
./jido_hive_client room submit \
  --api-base-url http://127.0.0.1:4000/api \
  --room-id <room-id> \
  --participant-id alice \
  --participant-role coordinator \
  --authority-level binding \
  --text "debug probe" \
  > submit.json \
  2> submit_trace.ndjson
```

Rules:

- JSON stays on stdout
- trace stays on stderr
- capture this before adding more logging

### 4. If the bug is execution-side, debug the worker runtime

This is the right layer for:

- target never appears in `/api/targets`
- worker never joins the room channel
- assignments never arrive
- provider execution fails before the contribution is published

Useful checks:

```bash
setup/hive targets
curl -sS http://127.0.0.1:4000/api/targets | jq
bin/client-worker --worker-index 1
```

If you need to run the worker package directly:

```bash
cd jido_hive_worker_runtime
mix escript.build
./jido_hive_worker --help
```

### 5. Only then run the UI

Web:

```bash
cd jido_hive_web
mix phx.server
```

TUI:

```bash
cd examples/jido_hive_console
mix escript.build
./hive console --local --participant-id alice --debug --room-id <room-id>
```

At this point you are testing:

- browser or terminal render state
- focus and selection
- local editor state
- overlays and presentation
- composition between presentation layer and the shared operator surface

If the bug is already visible headlessly or from `jido_hive_surface`, do not
stay here.

## Structured trace rule

For bash-first debugging, prefer:

```bash
cd jido_hive_client
JIDO_HIVE_CLIENT_LOG_LEVEL=debug \
./jido_hive_client room show --api-base-url http://127.0.0.1:4000/api --room-id <room-id> \
  > room.json \
  2> trace.ndjson
```

That keeps machine-readable output and trace output separate.

## Local `iex`

Use local `iex` only when bash-level reproduction is not enough.

Server:

```bash
cd jido_hive_server
iex -S mix phx.server
```

Client:

```bash
cd jido_hive_client
iex -S mix
```

Worker runtime:

```bash
cd jido_hive_worker_runtime
iex -S mix
```

Do not assume production remote shell attach exists as a supported workflow.
For production, prefer HTTP, headless client commands, and platform logs.
