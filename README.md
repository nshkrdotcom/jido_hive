# jido_hive

`jido_hive` is a monorepo with two sibling Mix projects:

- `jido_hive_server`: Phoenix collaboration server
- `jido_hive_client`: outbound local client runtime

The first working slice is a distributed collaboration loop:

1. the server exposes a relay websocket and room orchestration API
2. multiple local clients connect outbound and register Jido execution targets
3. the server opens a room, dispatches turns through the relay, and merges results into shared room state
4. room state captures shared instructions, tool activity, claims, evidence, and objections
5. the server derives GitHub and Notion publication drafts from that room state through registered `jido_integration` direct connectors

This slice is intentionally narrow. It proves the client-server architecture,
the Jido wiring, the collaboration packet flow, and a server-side publication
planning seam before live credentialed publish execution is layered on.

## Repo Layout

- `jido_hive_server/`: Phoenix server, relay channel, room orchestration, Jido OS/bootstrap
- `jido_hive_client/`: local relay worker, scripted executor, client CLI
- `docs/architecture.md`: architecture notes and next-phase plan
- `bin/server`: start the Phoenix server
- `bin/client`: start a generic local relay client
- `bin/client-architect`: start the default architect client
- `bin/client-skeptic`: start the default skeptic client
- `bin/demo-first-slice`: create a room and run the current collaboration slice

## First Slice

Current working path:

- relay registration through Phoenix channels
- target advertisement into `Jido.Integration.V2`
- room creation and snapshot fetch over HTTP
- first-slice orchestration across two clients
- shared room state with claim, evidence, publish-intent, and objection entries
- server-local GitHub and Notion direct target registration
- publication-plan drafts at `GET /api/rooms/:id/publication_plan`

Current deferred path:

- real ASM-backed Codex or Claude execution in the client process
- credentialed GitHub and Notion publish execution through `jido_integration`
- richer referee and dispute-resolution loops

## Quick Start

Start the server in one terminal:

```bash
bin/server
```

Start two local clients in separate terminals:

```bash
bin/client-architect
bin/client-skeptic
```

Run the first slice once both targets are connected:

```bash
bin/demo-first-slice
```

Inspect connected targets directly:

```bash
curl -sS http://127.0.0.1:4000/api/targets
```

Inspect the derived GitHub and Notion publication drafts after running the
first slice:

```bash
curl -sS http://127.0.0.1:4000/api/rooms/<room-id>/publication_plan
```

## Dependency Model

Both Mix apps now follow the same stable dependency policy as the cleaned
upstream repos:

- use sibling-relative `path:` dependencies when local checkouts exist
- fall back to pinned git refs when they do not
- do not vendor upstream repos under committed `deps/` trees

## Test

```bash
cd jido_hive_client && mix test
cd jido_hive_server && mix test
```
