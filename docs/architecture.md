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
- HTTP API for room creation, execution, publication planning, publication
  execution, and connector install/connection flows
- room lifecycle, referee planning, and collaboration-envelope assembly
- durable SQLite persistence for room snapshots, targets, and publication runs
- `Jido.Signal.Bus`
- `jido_os` bootstrap
- `Jido.Integration.V2` connector registration for `codex.exec.session`,
  `github.issue.create`, and `notion.pages.create`
- server-local direct target announcements for GitHub and Notion publication
  capabilities
- relay target advertisement into the control plane

### Client

`jido_hive_client` currently owns:

- outbound websocket connection to the relay topic
- target registration payloads
- local execution dispatch through `RelayWorker`
- real session execution through `Jido.Harness -> asm -> ASM`
- a CLI entrypoint suitable for running multiple local client processes

## Collaboration Envelope

The server now sends each turn as a versioned collaboration envelope:

- `schema_version`
- `room`
  - room id
  - brief
  - rules
  - current room status
- `referee`
  - phase
  - directives
  - open disputes
  - whether publication has been requested
- `turn`
  - phase
  - round
  - participant id and role
  - objective
  - strict JSON response contract
- `shared`
  - shared context entries
  - instruction log from prior turns
  - tool-call log from prior turns
  - artifact log from prior turns

The client turns that envelope into one `RunRequest` with a strict JSON-only
output contract. The returned `job.result` packet carries:

- top-level turn status
- summary
- structured actions
- tool events
- approvals
- artifacts
- full execution event stream
- normalized execution metadata

If a live provider returns prose or malformed JSON, the client performs one
follow-up repair run with tools disabled and the same contract so the server
still receives normalized actions when the underlying content is salvageable.

## Refereed Loop

The current room loop is:

1. clients join `relay:local`
2. clients send `relay.hello` and `target.upsert`
3. the server exposes registered targets through `RemoteExec` and mirrors compatible targets into `Jido.Integration.V2`
4. `POST /api/rooms` creates room state with participants and rules
5. `POST /api/rooms/:id/run` opens a proposal turn, a critique turn, and a
   resolution turn as needed; the API also accepts `turn_timeout_ms` for
   real-provider latency
6. each client receives `job.start`, executes locally, and returns `job.result`
7. the server merges result actions into shared context entries, disputes,
   turn histories, and publication run state

The referee currently drives three phases:

- `proposal`
- `critique`
- `resolution`

The resulting room state captures:

- claims
- evidence
- publish requests
- objections
- revisions
- decisions
- disputes
- completed turn records
- full execution metadata and event logs
- derived GitHub and Notion publication drafts
- durable publication run history

## Why This Shape

This keeps the trust boundary aligned with the Jido docs:

- local execution stays user-owned
- the server coordinates, but does not pretend to be the local runtime
- compatibility and target truth flow through `jido_integration`
- future publication workflows can reuse the same room state and review packets

## Current Gaps

1. Publication execution is real, but this repo does not automate the provider
   auth dance; the operator still needs to bring the provider code/token back to
   the install-complete endpoint.
2. The current referee is still a simple architect/skeptic/resolution protocol,
   not a generalized N-party protocol.
3. Persistence is durable and correct for this app slice, but still app-local
   SQLite rather than a multi-node store.
4. Publication readiness still depends on the room actually emitting a
   `publish_request` entry; live model runs can complete in `in_review` if they
   solve the disputes but do not request publication.
