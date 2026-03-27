# jido_hive

`jido_hive` is a small monorepo for a distributed AI collaboration loop:

- a Phoenix server owns rooms, turn orchestration, and shared state
- local clients connect outbound over websockets and advertise executable targets
- the server opens turns, clients execute locally, and results are merged into a room snapshot
- the server derives publication drafts from that room state for GitHub and Notion

If you just want to use it, the fastest path is: start the server, start two local clients, run the demo script, inspect the room snapshot.

If you want to develop on it, this README also covers the moving parts, API surface, dependency model, and the easiest places to extend.

## What Works Today

The current "first slice" is intentionally narrow but real:

- local clients register themselves through Phoenix channels
- the server exposes connected targets at `GET /api/targets`
- you can create a room over HTTP
- the server runs a two-turn collaboration loop across an `architect` and a `skeptic`
- client results become structured room entries like claims, evidence, publish requests, and objections
- the server derives a publication plan with GitHub issue and Notion page drafts

What it does not do yet:

- no real Codex or Claude execution yet in the client runtime
- no credentialed GitHub or Notion publish step yet
- no persistence yet; rooms and targets are in memory
- no referee or dispute-resolution loop beyond opening disputes from objections

## Repo Shape

This is not an umbrella app. It is two sibling Mix projects plus top-level helper scripts:

- `jido_hive_server/`: Phoenix server, room state, relay channel, publication planning
- `jido_hive_client/`: outbound relay client, CLI, scripted executor
- `docs/architecture.md`: concise architecture notes and near-term direction
- `bin/server`: starts the Phoenix server
- `bin/client`: starts a generic local client
- `bin/client-architect`: starts the default architect client
- `bin/client-skeptic`: starts the default skeptic client
- `bin/demo-first-slice`: waits for both clients, creates a room, runs the first slice, prints results

## Requirements

- Elixir `~> 1.19`
- Erlang/OTP 28

## Quick Start

Open four terminals.

In terminal 1, start the server:

```bash
bin/server
```

In terminal 2, start the architect client:

```bash
bin/client-architect
```

In terminal 3, start the skeptic client:

```bash
bin/client-skeptic
```

In a fourth terminal, run the demo:

```bash
bin/demo-first-slice
```

That script will:

1. poll `GET /api/targets` until both clients appear
2. create a room
3. run the first two-turn collaboration slice
4. print the final room snapshot
5. print the derived publication plan

Useful checks while it is running:

```bash
curl -sS http://127.0.0.1:4000/api/targets | jq
curl -sS http://127.0.0.1:4000/api/rooms/<room-id> | jq
curl -sS http://127.0.0.1:4000/api/rooms/<room-id>/publication_plan | jq
```

If you do not have `jq`, plain `curl` is fine.

## What You Should Expect To See

After the demo runs, the room snapshot should contain:

- two completed turns
- context entries with these types, in order:
  `claim`, `evidence`, `publish_request`, `objection`
- at least one open dispute created from the objection

The publication plan should report:

- `github.issue.create` as a compatible direct target on the server
- `notion.pages.create` as a compatible direct target on the server
- a GitHub draft body summarizing the room
- a Notion draft payload with child blocks

The GitHub and Notion pieces are drafts only right now. They prove the planning seam, not live publishing.

## Running It Manually

If you want to drive the flow yourself instead of using `bin/demo-first-slice`, use the API directly.

List targets:

```bash
curl -sS http://127.0.0.1:4000/api/targets
```

Create a room:

```bash
curl -sS -X POST http://127.0.0.1:4000/api/rooms \
  -H 'content-type: application/json' \
  -d '{
    "room_id": "room-manual-1",
    "brief": "Develop a distributed collaboration protocol for two AI clients.",
    "rules": ["Every objection must target a claim."],
    "participants": [
      {
        "participant_id": "architect",
        "role": "architect",
        "target_id": "target-architect",
        "capability_id": "codex.exec.session"
      },
      {
        "participant_id": "skeptic",
        "role": "skeptic",
        "target_id": "target-skeptic",
        "capability_id": "codex.exec.session"
      }
    ]
  }'
```

Run the first slice:

```bash
curl -sS -X POST http://127.0.0.1:4000/api/rooms/room-manual-1/first_slice \
  -H 'content-type: application/json' \
  -d '{}'
```

Fetch the room snapshot:

```bash
curl -sS http://127.0.0.1:4000/api/rooms/room-manual-1
```

Fetch the derived publication plan:

```bash
curl -sS http://127.0.0.1:4000/api/rooms/room-manual-1/publication_plan
```

## Mental Model

The current runtime is simple:

1. clients join a relay topic like `relay:workspace-local`
2. each client sends `relay.hello` and `target.upsert`
3. the server records those targets and mirrors compatible ones into `Jido.Integration.V2`
4. a room is created over HTTP with participants mapped to target IDs
5. `POST /api/rooms/:id/first_slice` opens an architect turn, then a skeptic turn
6. the server pushes `job.start` to the selected client
7. the client executes locally and returns `job.result`
8. the server merges structured actions into room state
9. publication drafts are built from the resulting room snapshot

This is the trust boundary the code is built around:

- local execution stays local
- the server coordinates, but does not impersonate the local runtime
- publication planning can be centralized without centralizing local execution

## User-Facing Commands

The top-level `bin/` scripts are the easiest way to use the repo.

### `bin/server`

Starts the Phoenix server from `jido_hive_server`.

Environment variables:

- `PORT`: HTTP port, default `4000`
- `PHX_SERVER`: already set by the script

### `bin/client`

Starts a generic local client from `jido_hive_client`.

Useful environment variables:

- `JIDO_HIVE_URL`: websocket URL, default `ws://127.0.0.1:4000/socket/websocket`
- `JIDO_HIVE_WORKSPACE_ID`: workspace ID, default `workspace-local`
- `JIDO_HIVE_RELAY_TOPIC`: relay topic, default `relay:$JIDO_HIVE_WORKSPACE_ID`
- `JIDO_HIVE_WORKSPACE_ROOT`: advertised workspace root, default repo root
- `PARTICIPANT_ROLE`: default `architect`
- `PARTICIPANT_ID`: default matches role
- `TARGET_ID`: default `target-$PARTICIPANT_ROLE`
- `USER_ID`: default `user-$PARTICIPANT_ROLE`
- `CAPABILITY_ID`: default `codex.exec.session`
- `SCRIPTED_ROLE`: default matches role

Example:

```bash
PARTICIPANT_ROLE=reviewer \
PARTICIPANT_ID=reviewer \
TARGET_ID=target-reviewer \
USER_ID=user-reviewer \
SCRIPTED_ROLE=architect \
bin/client
```

That example still uses the scripted executor, but advertises itself as a different participant.

### `bin/client-architect` and `bin/client-skeptic`

These are convenience wrappers around `bin/client` with the expected IDs and roles pre-filled.

### `bin/demo-first-slice`

This is the fastest smoke test for the whole system. It waits for `target-architect` and `target-skeptic`, creates a room, runs the slice, then prints the room and publication plan.

Useful environment variables:

- `JIDO_HIVE_API_BASE`: default `http://127.0.0.1:4000/api`
- `ROOM_ID`: default `room-<unix-timestamp>`

## API Surface

Current HTTP endpoints:

- `GET /api/targets`
- `POST /api/rooms`
- `GET /api/rooms/:id`
- `POST /api/rooms/:id/first_slice`
- `GET /api/rooms/:id/publication_plan`

Current websocket endpoint:

- `/socket`

Current relay events:

- client to server: `relay.hello`, `target.upsert`, `job.result`
- server to client: `job.start`

## Developer Guide

### Where To Start Reading

If you are new to the codebase, these are the highest-value files:

- `jido_hive_server/lib/jido_hive_server/collaboration.ex`
- `jido_hive_server/lib/jido_hive_server/collaboration/room_server.ex`
- `jido_hive_server/lib/jido_hive_server/collaboration/actions/open_turn.ex`
- `jido_hive_server/lib/jido_hive_server/collaboration/actions/apply_result.ex`
- `jido_hive_server/lib/jido_hive_server/remote_exec.ex`
- `jido_hive_server/lib/jido_hive_server/publications.ex`
- `jido_hive_server/lib/jido_hive_server_web/relay_channel.ex`
- `jido_hive_client/lib/jido_hive_client/relay_worker.ex`
- `jido_hive_client/lib/jido_hive_client/cli.ex`
- `jido_hive_client/lib/jido_hive_client/executor/scripted.ex`

### Server Responsibilities

`jido_hive_server` currently owns:

- the Phoenix websocket relay at `/socket`
- room lifecycle and in-memory room state
- turn orchestration
- target discovery and remote job dispatch
- `Jido.Signal.Bus`
- `jido_os` bootstrap for the default system instance
- `Jido.Integration.V2` connector registration
- server-local direct targets for GitHub and Notion publication planning

### Client Responsibilities

`jido_hive_client` currently owns:

- connecting outbound to the relay topic
- advertising local execution targets
- accepting `job.start`
- executing locally through an executor module
- returning structured actions and tool events as `job.result`

### Current Room State Shape

A room snapshot contains, at minimum:

- `room_id`
- `brief`
- `rules`
- `participants`
- `turns`
- `context_entries`
- `disputes`
- `current_turn`
- `status`

Structured action ops currently map to room entry types like this:

- `CLAIM` -> `claim`
- `EVIDENCE` -> `evidence`
- `OBJECT` -> `objection`
- `REVISE` -> `revision`
- `DECIDE` -> `decision`
- `PUBLISH` -> `publish_request`

An objection automatically opens a dispute.

### How To Extend It

To add a new client behavior:

1. implement the `JidoHiveClient.Executor` behaviour
2. pass that executor into `RelayWorker`
3. return structured `actions`, a `summary`, and optional `tool_events`

To add new room semantics:

1. teach the client to emit a new action shape
2. update `ApplyResult` to map or interpret it
3. update `Publications` or downstream consumers if the new state should affect drafts

To add a new publication target:

1. register the connector in `IntegrationsBootstrap`
2. announce any direct server-side targets if appropriate
3. extend `JidoHiveServer.Publications` with a new publication spec and draft builder

### Dependency Model

Dependencies are intentionally resolved in a developer-friendly way:

- if sibling repos like `../jido`, `../jido_harness`, or `../jido_integration/...` exist, Mix uses local `path:` dependencies
- otherwise it falls back to pinned GitHub refs declared in `build_support/dependency_resolver.exs`

That means you can work against local sibling checkouts when doing multi-repo development, but the repo still boots without vendoring those dependencies into this tree.

### Running Tests

Run tests per app:

```bash
cd jido_hive_client
mix test

cd ../jido_hive_server
mix test
```

Good server-side tests to read first:

- `jido_hive_server/test/jido_hive_server/collaboration/relay_slice_test.exs`
- `jido_hive_server/test/jido_hive_server/publications_test.exs`
- `jido_hive_server/test/jido_hive_server_web/controllers/room_controller_test.exs`

Good client-side test to read first:

- `jido_hive_client/test/jido_hive_client/executor/scripted_test.exs`

## Practical Notes

- The top-level repo itself is not a Mix project. Use the `bin/` scripts or run Mix commands inside `jido_hive_server/` and `jido_hive_client/`.
- The current server binds to `127.0.0.1` in development.
- Restarting the server clears connected targets and room state.
- The default client executor is scripted and deterministic, which makes the current slice easy to test and reason about.

## Near-Term Direction

The current code clearly points toward the next steps:

- replace the scripted executor with a real ASM-backed session runtime
- define a richer collaboration envelope for prompts, tool calls, approvals, and artifacts
- add referee and dispute-resolution logic
- turn publication drafts into real connector-backed publish flows
- persist room state and execution references

For a compact architecture summary, read `docs/architecture.md`.
