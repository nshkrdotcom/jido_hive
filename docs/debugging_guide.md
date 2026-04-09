# Jido Hive Debugging Guide

This is the general debugging workflow for `jido_hive`.

Use it when a room looks stale, a mutation appears to hang, the TUI shows the
wrong state, or you need to decide whether a bug belongs to the server, the
client, or the console.

The governing rule is:

1. server truth first
2. headless client second
3. TUI last

If a behavior reproduces from the headless client, it is not a TUI-only bug.

## What each layer owns

- `jido_hive_server`
  - authoritative room truth
  - timeline truth
  - contribution reduction
  - publication planning and execution
  - connector install and connection state
- `jido_hive_client`
  - reusable operator workflows
  - room-scoped session behavior
  - headless CLI for shell scripts and reproduction
- `examples/jido_hive_termui_console`
  - terminal rendering
  - key handling
  - routing and screen state
  - draft buffers, focus, overlays, selection

## The standard triage sequence

Use one bug, one room, one sequence.

### 1. Pick the room

Use either:

- the exact failing room, or
- a fresh room created specifically for reproduction

Always capture the `room_id`.

### 2. Confirm server truth first

Start here before touching the TUI.

```bash
setup/hive --prod server-info
curl -sS https://jido-hive-server-test.app.nsai.online/api/rooms/<room-id> | jq
curl -sS https://jido-hive-server-test.app.nsai.online/api/rooms/<room-id>/timeline | jq
```

Questions this answers:

- Does the server think the room is `idle`, `running`, or `publication_ready`?
- Does the room already contain context or contributions?
- Is the timeline moving even if the TUI looks frozen?

If server truth is wrong, stop blaming the client or TUI.

### 3. Reproduce through the headless client

This is the main seam test.

```bash
cd jido_hive_client
mix escript.build

./jido_hive_client room show \
  --api-base-url https://jido-hive-server-test.app.nsai.online/api \
  --room-id <room-id> | jq

./jido_hive_client room tail \
  --api-base-url https://jido-hive-server-test.app.nsai.online/api \
  --room-id <room-id> | jq
```

Questions this answers:

- Can the client see the same room truth as raw HTTP?
- Is the room stale only in the console?
- Is the bug already present before the TUI is involved?

### 4. Reproduce the human action headlessly with trace

Use this for submit/accept/resolve style bugs.

```bash
JIDO_HIVE_CLIENT_LOG_LEVEL=debug \
./jido_hive_client room submit \
  --api-base-url https://jido-hive-server-test.app.nsai.online/api \
  --room-id <room-id> \
  --participant-id alice \
  --participant-role coordinator \
  --authority-level binding \
  --text "debug probe" \
  > submit.json \
  2> submit_trace.ndjson
```

You can swap in:

- `room accept`
- `room resolve`
- `room publish`

Questions this answers:

- Did the request actually leave the client?
- Did the server accept it?
- Did the client wedge before or after the server response?

### 5. If the bug is about room execution, reproduce `room run` headlessly

```bash
JIDO_HIVE_CLIENT_LOG_LEVEL=debug \
./jido_hive_client room run \
  --api-base-url https://jido-hive-server-test.app.nsai.online/api \
  --room-id <room-id> \
  --max-assignments 1 \
  --assignment-timeout-ms 60000 \
  --request-timeout-ms 90000 \
  > run.json \
  2> run_trace.ndjson
```

Questions this answers:

- Is the timeout happening in the operator transport path?
- Is the server run endpoint actually returning?
- Is the TUI only surfacing a client/server timing issue that already exists headlessly?

### 6. Only then run the TUI against the same room

```bash
cd examples/jido_hive_termui_console
mix escript.build
./hive console --prod --participant-id alice --debug --room-id <room-id>
```

Useful companion tail:

```bash
tail -f ~/.config/hive/termui_console.log
```

At this point you are testing:

- render state
- focus
- key handling
- stale screen transitions
- popup/help flows
- presentation of already-understood server/client behavior

### 7. Compare outcomes

Use this ownership matrix:

- server wrong + headless wrong + TUI wrong
  - server bug
- server right + headless wrong + TUI wrong
  - client bug
- server right + headless right + TUI wrong
  - TUI bug

This is the shortest path to responsibility assignment.

### 8. If headless is still ambiguous, use local `iex`

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

Use local `iex` when bash-level reproduction is not enough.

Do not assume production remote-shell attach exists as a supported workflow.
For production, prefer:

- direct HTTP
- headless CLI
- structured stderr trace
- Coolify logs

## Structured trace rules

The preferred debug trace path is:

```bash
JIDO_HIVE_CLIENT_LOG_LEVEL=debug \
./jido_hive_client room show --api-base-url https://jido-hive-server-test.app.nsai.online/api --room-id <room-id> \
  > room.json \
  2> trace.ndjson
```

Rules:

- stdout stays machine-readable
- stderr carries debug trace
- do this before adding more ad hoc logging

Trace events include:

- `headless.command.started`
- `headless.command.completed`
- `headless.command.failed`
- `operator.http.request.started`
- `operator.http.request.completed`
- `operator.http.request.failed`
- `room_session.submit_chat.started`
- `room_session.submit_chat.completed`
- `room_session.submit_chat.failed`

## Minimal reproduction data to collect

If you need someone else to investigate, gather:

- exact `room_id`
- exact command used
- raw HTTP result or relevant route output
- headless CLI stdout
- headless CLI trace file
- TUI log line or screenshot

With that set, someone can usually assign the bug to server, client, or TUI
quickly.
