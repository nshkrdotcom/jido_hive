# Architecture

## Direction

This repo follows the generalized Jido app split from the local design docs:

- Phoenix owns rooms, participants, room protocol, and operator UX
- `jido_integration` owns durable execution truth and target compatibility
- `jido_harness` stays the runtime seam into ASM-backed session execution
- local clients own user-local execution and connect outbound to the server

The repo is intentionally not an umbrella app. The server and client are independent Mix projects that share architecture, not OTP supervision trees.

## Current Runtime

### Server

`jido_hive_server` currently owns:

- Phoenix websocket relay at `/socket`
- HTTP API for `GET /api/targets`, `POST /api/rooms`, `GET /api/rooms/:id`, and `POST /api/rooms/:id/first_slice`
- room lifecycle and room-state accumulation
- `Jido.Signal.Bus`
- `jido_os` bootstrap
- `Jido.Integration.V2` connector registration for `codex.exec.session`
- relay target advertisement into the control plane

### Client

`jido_hive_client` currently owns:

- outbound websocket connection to the relay topic
- target registration payloads
- local execution dispatch through `RelayWorker`
- deterministic scripted executors for the first slice
- a CLI entrypoint suitable for running multiple local client processes

## First-Slice Protocol

The current room loop is:

1. clients join `relay:local`
2. clients send `relay.hello` and `target.upsert`
3. the server exposes registered targets through `RemoteExec` and mirrors compatible targets into `Jido.Integration.V2`
4. `POST /api/rooms` creates room state with participants and rules
5. `POST /api/rooms/:id/first_slice` opens one architect turn and one skeptic turn
6. each client receives `job.start`, executes locally, and returns `job.result`
7. the server merges result actions into shared context entries and disputes

The first slice shares:

- brief
- rules
- context summary
- shared instruction log
- shared tool log

The resulting room state captures:

- claims
- evidence
- objections
- disputes
- completed turn records

## Why This Shape

This keeps the trust boundary aligned with the Jido docs:

- local execution stays user-owned
- the server coordinates, but does not pretend to be the local runtime
- compatibility and target truth flow through `jido_integration`
- future publication workflows can reuse the same room state and review packets

## Near-Term Next Steps

1. Replace the scripted client executor with real ASM-backed session execution via `jido_harness` and `agent_session_manager`.
2. Introduce a stable collaboration envelope for prompts, tool calls, partial results, approvals, and streamed artifacts.
3. Add referee logic for objection targeting, turn admission, and dispute resolution.
4. Re-enable GitHub and Notion publication flows through `jido_integration` connectors once the current connector compile path is stabilized in this environment.
5. Persist room state and execution references instead of keeping them in memory.
