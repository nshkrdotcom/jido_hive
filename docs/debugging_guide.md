# Jido Hive Debugging Guide

This is the default debugging order for `jido_hive`.

Use it when:

- a room looks stale
- a mutation appears to hang
- a worker is not registering
- a run operation is blocked
- the TUI shows something that looks wrong

The governing rule is:

1. server truth first
2. headless operator client second
3. worker runtime third if the bug involves relay targets or assignment execution
4. TUI last

If a behavior reproduces from the headless client, it is not a TUI-only bug.

## Current transport split

Today the system uses two transport styles:

- operator surfaces use the HTTP API
- workers use the websocket relay

That means:

- `setup/hive` is an HTTP-oriented operator/tooling surface
- `jido_hive_client room ...` commands are HTTP-backed
- the Switchyard-backed console is HTTP-backed for room inspection and human
  actions
- `bin/client` and `bin/client-worker` launch websocket relay workers through
  `jido_hive_worker_runtime`

## What each layer owns

- `jido_hive_server`
  authoritative room truth, timeline truth, reduction, publications, connector
  state
- `jido_hive_client`
  reusable operator workflows, room-scoped local session behavior, headless CLI
- `jido_hive_worker_runtime`
  relay worker registration, assignment delivery, local execution, worker-local
  runtime state
- Switchyard plus `examples/jido_hive_console`
  terminal rendering, routing, local screen state, key handling

## Standard triage sequence

Use one bug, one room, one sequence.

### 1. Confirm server truth

Start here before touching the client or TUI.

```bash
setup/hive server-info
curl -sS http://127.0.0.1:4000/api/rooms/<room-id> | jq
curl -sS http://127.0.0.1:4000/api/rooms/<room-id>/timeline | jq
```

Questions this answers:

- does the server think the room is `idle`, `running`, `blocked`, or
  `publication_ready`?
- does the room already contain the contribution or context object you expect?
- is the timeline moving even if the console looks stale?

If server truth is wrong, stop blaming the client or TUI.

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

### 3. Reproduce the human action headlessly with trace

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
- worker never joins the relay
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

### 5. Only then run the TUI

```bash
cd examples/jido_hive_console
mix escript.build
./hive console --local --participant-id alice --debug --room-id <room-id>
```

At this point you are testing:

- render state
- focus and selection
- local editor state
- overlays and presentation
- composition between Switchyard and `jido_hive_client`

If the bug is already visible headlessly, do not stay here.

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
