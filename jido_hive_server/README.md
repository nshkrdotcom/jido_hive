# JidoHiveServer: Room Authority & Context Store

`jido_hive_server` is the authoritative coordinator for the `jido_hive` participation substrate.

The server does **not** know about specific workflows, collaboration styles, or application semantics. It is purely responsible for:
- Managing **Room** lifecycles (the shared epistemic space).
- Executing pluggable **Dispatch Policies**.
- Storing **Context Objects** with full provenance tracking.
- Maintaining the registry of **Participants** (workers and humans).
- Managing live worker coordination over the Phoenix WebSocket Relay.
- Providing persistence (SQLite via Ecto) and publication execution (GitHub, Notion).

If you are new to the architecture, read the top-level concepts in [../README.md](../README.md).

## From Workflows to Dispatch Policies

Historically, the server hardcoded workflow steps (e.g., proposal, critique). Now, the server delegates all orchestration to **Dispatch Policies**. 

A Dispatch Policy asks: *Given the current room state and the available participants, who should produce the next context object, and what should their input view be?*

Built-in policies included in the library:
- `round_robin/v2`: Sequential turns across a defined set of participants (collaborative reasoning).
- `resource_pool/v1`: Matches pending tasks to participants based on available compute/capabilities (hands-off execution).
- `human_gate/v1`: Pauses execution until a human participant produces a decision node.

## Data Model & Provenance

The server maintains pure functional data structures representing the substrate:

- **Assignments**: Created by the dispatch policy. They don't carry full mutable room state. They carry a scoped `context_view` (what the worker is allowed to see) and a `contribution_contract` (what the worker is allowed to output).
- **Contributions**: Incoming payloads from participants. The server validates that the contribution satisfies the assignment's contract.
- **Context Objects**: Extracted from validated contributions by the `EventReducer`. Every object (e.g., `belief`, `note`, `decision`) is persisted with strict **provenance**: who authored it, based on what relations, and with what authority level.

## Key APIs & Boundaries

### REST Control Plane
The REST API is how operators (and UI clients) inspect the substrate and how human participants inject manual context objects.

- `POST /api/rooms` - Create a room, attaching a `dispatch_policy_id` and config.
- `GET /api/policies` - List available pluggable dispatch policies.
- `GET /api/rooms/:id/context_objects` - View the typed knowledge objects accumulated in the room.
- `POST /api/rooms/:id/contributions` - **How humans participate.** Submit a manual contribution matching the exact same schema as an LLM worker.
- `GET /api/rooms/:id/events` - The raw, canonical event log.
- `GET /api/rooms/:id/timeline` - A UI-friendly projection of the events (supports `?after=<cursor>` and `?stream=true` for SSE).
- `POST /api/rooms/:id/run` - Trigger the dispatch policy loop.

### The Relay Transport
Live workers use Phoenix WebSockets for low-latency coordination. State is **never** sent peer-to-peer.
- Client pushes: `relay.hello`, `participant.upsert` (declaring capabilities), `contribution.submit`.
- Server pushes: `assignment.start`.

## Quick Start

```bash
# Starts the server with Ecto creation & migration
bin/server
```
Local endpoint: `http://127.0.0.1:4000`

## Developer Guidance

The server is built with a strict separation between pure logic and side-effects.

- **Functional Core (`lib/jido_hive_server/collaboration/`)**: This is the heart of the substrate. It contains the data schemas (`Schema/`), pure state transitions (`EventReducer`, `CommandHandler`), context projections (`ContextView`), and the `DispatchPolicy` behaviours.
- **Boundaries (`lib/jido_hive_server_web/`)**: Controllers and the `RelayChannel`. They normalize HTTP/WS payloads and delegate to the core.
- **Lifecycle / OTP (`lib/jido_hive_server/collaboration/room_server.ex`)**: Wraps the pure `RoomAgent` to handle concurrency and persistence.

**Rule of thumb:** Do not put room-state business logic in controllers or channels. Do not put Ecto queries or HTTP calls in the Collaboration core.

## Production and Deployment

The current deployed base is `https://jido-hive-server-test.app.nsai.online`.
Deploys are managed via `coolify_ex`.

From the repo root:
```bash
scripts/deploy_coolify.sh
```

Follow up by tailing the logs:
```bash
cd jido_hive_server
MIX_ENV=coolify mix coolify.app_logs --project server --lines 200 --follow
```