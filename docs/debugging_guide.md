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

## Current transport split

Today the system uses two different transport styles:

- workers use the websocket relay for assignment delivery and execution
- operator surfaces use the HTTP API through explicit transport lanes

That means:

- `bin/client-worker` and `bin/client` are websocket clients
- `jido_hive_client room ...` headless commands are HTTP clients
- the ExRatatui console is also HTTP-backed for room inspection and human actions

The operator HTTP path is now intentionally lane-based. The important lanes are:

- `operator_control`
- `operator_room`
- `operator_timeline`
- `room_hydrate`
- `room_sync`
- `room_submit`
- `room_run_control`
- `lobby_hydrate`

Every HTTP request from the shared client transport should now log:

- `surface`
- `lane`
- `operation_id`
- `method`
- `path`
- `timeout_ms`
- `elapsed_ms`

If a timeout occurs and those fields are missing, that is now an observability regression.

For the console room screen specifically, the expected live pattern is:

- one initial `GET /rooms/:id` when the room is opened
- repeated `GET /rooms/:id/timeline?after=...` polling while the room is open
- occasional `GET /rooms/:id/context_objects` and `GET /rooms/:id` only when
  new timeline entries arrive or an explicit refresh is requested

If you see repeated `GET /rooms/:id` requests during steady-state room viewing,
or a second independent timeline poller, that is a regression in the
room-refresh seam between the console and the room session, not expected
behavior.

The room run path is also no longer modeled as a single blocking request in the
console. The preferred contract is:

- start run: accepted immediately as a run operation
- poll run operation state separately
- keep room sync and human submit independent of run startup

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
  - worker contribution prompt shaping and contribution normalization
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
- Is the server already recording the message or worker contribution even if the
  console has not caught up yet?

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
- Is the client-side room snapshot already correct before any rendering code runs?

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
  > run_start.json \
  2> run_trace.ndjson
```

Questions this answers:

- Did the server accept a run operation and return an `operation_id` immediately?
- Is the timeout happening during operation start or later during operation polling?
- Is the TUI only surfacing a client/server timing issue that already exists headlessly?

Important run-operation note:

- human-facing tools may log both a `client_operation_id` and a `server_operation_id`
- use the `server_operation_id` for `run-status` and direct `/run_operations/:operation_id` fetches
- use the `client_operation_id` only for correlating local transport/start logs

Preferred run-operation checks:

```bash
curl -sS https://jido-hive-server-test.app.nsai.online/api/rooms/<room-id>/run_operations/<operation-id> | jq

./jido_hive_client room run-status \
  --api-base-url https://jido-hive-server-test.app.nsai.online/api \
  --room-id <room-id> \
  --operation-id <operation-id> | jq
```

If you do not have a `server_operation_id`, capture it from the console debug popup,
console log, client stderr trace, or transport logs first.

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

Expected debug-log shape after the room opens:

- one `operator http request ... path=/rooms/<room-id>`
- many `operator http request ... path=/rooms/<room-id>/timeline?after=...`

Expected transport-log shape now:

- `transport http request started surface=... lane=... operation_id=...`
- `transport http request completed surface=... lane=... operation_id=...`
- or `transport http request failed ...`

That is the current design. It is noisy, but it is bounded and predictable.

For human submit bugs, the expected console lifecycle is:

1. `room chat submit started ... op=<id>` in the console log
2. `room_submit_accepted` state in the TUI/app path
3. room snapshot `operations` entry for that `operation_id`
4. reconciliation to either:
   - `Submitted chat message`
   - or `Submit failed: ...`

If the server never sees `POST /api/rooms/<room-id>/contributions`, the bug is
still client-side, but the lane and operation id should now tell you exactly
which boundary stalled.

If you also see worker contribution failures that mention invented relation
targets, such as `target_id: "brief-topic"`, treat that as a client-side
contribution-shaping bug. The current client contract is:

- when no room context ids are visible, workers must emit `relations: []`
- when room context ids are visible, relation targets must be chosen only from
  that visible set

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

When debugging submit/run contention, prefer traces that preserve the operation id:

```bash
JIDO_HIVE_CLIENT_LOG_LEVEL=debug \
./jido_hive_client room submit ... \
  > submit.json \
  2> submit_trace.ndjson
```

Then correlate:

- `client_operation_id` in stderr trace
- `client_operation_id` and `server_operation_id` in console log
- `operation_id` in transport log lines
- server request path and status

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
