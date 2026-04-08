# JidoHiveClient

`jido_hive_client` is the participant runtime for `jido_hive`.

It exists to let a participant take part in a room without moving room authority
out of the server. In practice that means two related roles:

- a long-running worker runtime connected to the websocket relay
- an embedded local runtime used directly from Elixir applications such as the
  terminal UI example

The client is deliberately narrower than the server. It should be easy to run,
easy to embed, and easy to reason about. The room still decides what is true.

If you are onboarding, start with the root [README](../README.md). If you are
working on the room model, read the server [README](../jido_hive_server/README.md)
next.

## Table of contents

- [What this package is for](#what-this-package-is-for)
- [Responsibilities and boundaries](#responsibilities-and-boundaries)
- [Two runtime modes](#two-runtime-modes)
- [Worker execution flow](#worker-execution-flow)
- [Embedded human-facing flow](#embedded-human-facing-flow)
- [Interceptor and mock backend](#interceptor-and-mock-backend)
- [Local diagnostics surface](#local-diagnostics-surface)
- [CLI usage and configuration](#cli-usage-and-configuration)
- [Development notes](#development-notes)
- [Related docs](#related-docs)

## What this package is for

`jido_hive_client` is the execution and participation boundary for participants.

It is responsible for:

- connecting to the server relay
- identifying itself as a participant
- receiving assignments
- executing local work through the configured executor
- submitting structured contributions back to the room
- exposing local runtime state when a developer or tool needs to inspect it
- embedding directly into local Elixir applications when a human-facing tool does
  not want a separate daemon process

It is not responsible for:

- deciding room truth
- dispatching the next assignment
- persisting the room
- running server-side context reasoning

The recent context-graph and context-manager work happened on the server. The
client consumes the richer room surfaces that result from that work, but it does
not need to own that logic.

## Responsibilities and boundaries

The clean mental model is:

- server = authority
- client = participant runtime
- example UI = a consumer of the client runtime

That separation is why the same room can be served to both:

- workers operating over the relay
- local human-facing tools built against `JidoHiveClient.Embedded`

The client should stay opinionated about participation mechanics and relatively
unopinionated about room semantics beyond the contracts it has to honor.

## Two runtime modes

This package currently supports two main modes.

### 1. Worker mode

Worker mode is the daemon-style runtime used by:

- `bin/client-worker`
- `bin/hive-clients`
- the local and production smoke flows

In this mode the client joins the websocket relay and waits for assignments from
the server.

### 2. Embedded mode

Embedded mode is the in-process Elixir API used by local tools.

The main entry point is:

- `JidoHiveClient.Embedded`

This mode is used by:

- `examples/jido_hive_termui_console`
- future local tools that want a human-friendly participation path without
  shelling out to a separate HTTP client process

Embedded mode does not replace the server. It packages participant-side behavior
for local tools while still submitting contributions to the authoritative room.

## Worker execution flow

The worker runtime is intentionally straightforward.

### Lifecycle

1. The CLI parses options and configures the runtime.
2. The client starts `JidoHiveClient.Runtime`.
3. The relay worker connects to the websocket URL.
4. The worker joins the configured relay topic.
5. The participant identity is upserted to the server.
6. The worker waits for `assignment.start`.
7. The configured executor performs local work.
8. The worker submits `contribution.submit`.
9. The room advances and the worker waits for the next assignment.

### Typical local invocation

```bash
bin/client-worker --worker-index 1
```

Run a second worker:

```bash
bin/client-worker --worker-index 2
```

The `bin/` wrappers are the preferred operator path because they fill in sane
defaults and line up with the repo demo flow.

## Embedded human-facing flow

`JidoHiveClient.Embedded` exists so local applications can participate in rooms
without running a separate client daemon or reimplementing room API plumbing.

The current embedded surface is intentionally small:

- `start_link/1`
- `snapshot/1`
- `subscribe/1`
- `submit_chat/2`
- `accept_context/3`
- `refresh/1`
- `shutdown/1`

### What the embedded runtime does

When started, the embedded runtime:

- creates or reuses a local runtime process
- subscribes to runtime events
- polls the room timeline and context surfaces
- keeps a local snapshot of timeline entries and context objects
- accepts human chat text and turns it into structured contributions
- posts those contributions back to the server

### Selected-context-aware authoring

The embedded chat path now carries enough local context to shape the server-side
graph deliberately instead of treating human chat as ungrounded free text.

The current local context contract supports:

- `selected_context_id`
- `selected_context_object_type`
- `selected_relation`
- `authority_level`

Supported relation modes are:

- `contextual`
- `references`
- `derives_from`
- `supports`
- `contradicts`
- `resolves`
- `none`

Behavior:

- `contextual` uses a simple per-object default relation
- explicit canonical relation modes use that exact relation to the selected node
- `none` submits plain chat with no graph anchoring
- `authority_level` is threaded from `submit_chat/2` into `ChatInput`, the
  intercepted contribution, and the final contribution payload
- if a selected context exists and heuristics would otherwise emit only a
  `message`, the mock backend adds one anchored `note` so the action can still
  shape the graph

Current contextual defaults are intentionally narrow:

- `hypothesis` -> `derives_from`
- `evidence` -> `supports`
- `contradiction` -> `contradicts`
- `decision` -> `resolves`
- `decision_candidate` -> `resolves`
- `question` -> `references`
- `note` -> `references`

### Authority threading

`submit_chat/2` now accepts `authority_level` explicitly.

Behavior:

- `ChatInput.new/1` defaults `authority_level` to `"advisory"` when absent
- embedded human tools can pass `"binding"` when they need the chat-derived
  contribution to carry binding authority
- this is the Path A chat flow only
- direct HTTP contribution posts remain a separate Path B and are used by the
  TUI conflict-resolution screen for its one-object-two-`resolves` submission

### Conceptual example

```elixir
{:ok, embedded} =
  JidoHiveClient.Embedded.start_link(
    room_id: "room-123",
    participant_id: "alice",
    participant_role: "collaborator",
    api_base_url: "http://127.0.0.1:4000/api"
  )

:ok = JidoHiveClient.Embedded.subscribe(embedded)

{:ok, _contribution} =
  JidoHiveClient.Embedded.submit_chat(embedded, %{
    text: "I think Redis is dropping connections",
    authority_level: "binding"
  })

snapshot = JidoHiveClient.Embedded.snapshot(embedded)
```

That is the exact integration style used by the terminal UI example in
`../examples/jido_hive_termui_console`.

### Accepting context

The embedded runtime also supports `accept_context/3`, which lets a human-facing
tool turn the currently selected context object into a binding decision-style
contribution. That is how the first TUI supports "accept selected context object"
without needing direct knowledge of the room contribution schema.

The current accept path emits a canonical `decision` object that
`derives_from` the selected context id, so the server-side context graph can use
it immediately.

## Interceptor and mock backend

Human chat does not go straight to the server as raw text. The client provides a
narrow interception pipeline that turns human input into structured
contributions.

Important modules:

- `JidoHiveClient.ChatInput`
- `JidoHiveClient.InterceptedContribution`
- `JidoHiveClient.Interceptor`
- `JidoHiveClient.AgentBackend`
- `JidoHiveClient.AgentBackends.Mock`

### Why the mock backend exists

The mock backend is deliberate. It lets UI and runtime development move forward
without blocking on a live model provider every time a developer wants to test a
human-facing flow.

Current mock heuristics are deterministic and intentionally simple:

- every chat message yields a `message` object
- `I think` tends to produce a `hypothesis`
- `because` tends to produce `evidence`
- `?` tends to produce a `question`
- `no`, `actually`, or `broken` can produce a `contradiction`
- `we should` or `let's` can produce a `decision_candidate`

The point is not to be clever. The point is to produce stable structured
contributions that exercise the rest of the stack.

The important recent change is that the mock backend is now selected-context
aware:

- it can anchor generated semantic objects to the selected context
- it honors explicit relation modes
- it never emits nil-target relations
- it can synthesize an anchored note when a selected context exists but the
  heuristics would otherwise only emit a plain message

## Local diagnostics surface

The client can expose a small local REST and SSE diagnostics API. This is useful
when developing worker behavior or debugging local execution.

Enable it with:

```bash
bin/client-worker --worker-index 1 --control-port 4101
```

Current routes:

- `GET /api/runtime`
- `GET /api/runtime/assignments`
- `GET /api/runtime/events`
- `GET /api/runtime/events?stream=true`
- `POST /api/runtime/assignments/execute`

This diagnostics surface is intentionally local. It does not replace the server
APIs and it does not become a second orchestration authority.

## CLI usage and configuration

The escript entrypoint is `JidoHiveClient.CLI`.

### Common options

- `--url`
  Websocket URL. Default:
  `ws://127.0.0.1:4000/socket/websocket`
- `--relay-topic`
  Relay topic. Default: `relay:<workspace-id>`
- `--workspace-id`
  Default: `workspace-local`
- `--user-id`
  Default: `user-local`
- `--participant-id`
  Default: `participant-local`
- `--participant-role`
  Default: `architect`
- `--target-id`
  Default: `target-local`
- `--capability-id`
  Default: `codex.exec.session`
- `--workspace-root`
  Default: current working directory
- `--provider`
  Default: `codex`
- `--model`
  Optional model override
- `--reasoning-effort`
  Default: `low`
- `--timeout-ms`
  Optional executor timeout
- `--cli-path`
  Optional custom executor CLI path
- `--control-port`
  Enables the local diagnostics API
- `--control-host`
  Default: `127.0.0.1`

Environment-driven diagnostics settings:

- `JIDO_HIVE_CLIENT_CONTROL_PORT`
- `JIDO_HIVE_CLIENT_CONTROL_HOST`
- `JIDO_HIVE_CLIENT_LOG_LEVEL`

### Raw invocation example

```bash
mix run --no-halt -e 'JidoHiveClient.CLI.main(System.argv())' -- \
  --url ws://127.0.0.1:4000/socket/websocket \
  --relay-topic relay:workspace-local \
  --workspace-id workspace-local \
  --participant-id worker-1 \
  --participant-role analyst \
  --target-id target-worker-1 \
  --capability-id codex.exec.session \
  --provider codex \
  --model gpt-5.4 \
  --reasoning-effort high
```

In normal repo usage you should still prefer the root wrappers because they
encode the expected operator flow.

## Development notes

Useful client areas:

- `lib/jido_hive_client/relay_worker.ex`
  Relay-connected participant runtime.
- `lib/jido_hive_client/runtime/`
  Runtime state tracking and event recording.
- `lib/jido_hive_client/boundary/`
  Room API and transport boundary code.
- `lib/jido_hive_client/embedded.ex`
  In-process embedded runtime.
- `lib/jido_hive_client/interceptor.ex`
  Human input to structured contribution pipeline.
- `lib/jido_hive_client/agent_backends/mock.ex`
  Deterministic backend used by embedded flows and tests.
- `lib/jido_hive_client/control/`
  Local diagnostics API.

### Setup

From the repo root:

```bash
bin/setup
```

### Focused client quality gate

```bash
cd jido_hive_client
mix quality
```

### Repo-wide quality gate

```bash
cd ..
mix ci
```

Use the repo-wide gate when your change affects shared behavior, docs, scripts,
or multiple packages.

## Related docs

- [Root README](../README.md)
- [Server README](../jido_hive_server/README.md)
- [Console example README](../examples/jido_hive_termui_console/README.md)
