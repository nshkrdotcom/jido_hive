# JidoHiveClient

`jido_hive_client` is the participant runtime for `jido_hive`.

It serves two related use cases:
- long-running worker processes connected to the server relay
- embedded local runtimes used directly from Elixir applications such as the TUI example

If you are onboarding, start with the repo root [README](../README.md).

## What the client does

The client is the execution and participation boundary. It:
- connects to the server relay as a participant
- receives structured assignments
- executes local work against a contribution contract
- returns structured contributions
- exposes a local runtime/control surface when needed
- now also supports direct in-process embedding for human-facing tools

## Two client modes

### 1. Worker mode

Worker mode is the existing daemon-style execution flow used by:
- `bin/client-worker`
- `bin/hive-clients`
- server-driven assignment execution

In this mode the client:
1. joins the Phoenix relay
2. registers itself with `participant.upsert`
3. waits for `assignment.start`
4. executes locally through the configured executor
5. submits `contribution.submit`

### 2. Embedded mode

Embedded mode is the new direct Elixir API for local tools.

The main entry point is:
- `JidoHiveClient.Embedded`

Current embedded operations are:
- `start_link/1`
- `snapshot/1`
- `subscribe/1`
- `submit_chat/2`
- `accept_context/3`
- `refresh/1`
- `shutdown/1`

This API is intentionally narrow. It is designed to be consumed by local tools without adding another orchestration layer.

## Mock-first interception

For human-first collaboration flows, the client now includes a narrow interceptor boundary and a deterministic mock backend.

Key modules:
- `JidoHiveClient.ChatInput`
- `JidoHiveClient.InterceptedContribution`
- `JidoHiveClient.Interceptor`
- `JidoHiveClient.AgentBackend`
- `JidoHiveClient.AgentBackends.Mock`

The mock backend exists so UI and runtime development can move quickly without waiting on a real LLM every time a human submits text.

Current mock heuristics intentionally stay simple:
- chat message always yields a `message` object
- `I think` tends to yield a `hypothesis`
- `because` tends to yield `evidence`
- `?` tends to yield a `question`
- `no`, `actually`, or `broken` can yield a `contradiction`
- `we should` or `let's` can yield a `decision_candidate`

The result is a deterministic structured contribution that the room can store immediately.

## Local control API

The client can expose a local REST and SSE surface for diagnostics and isolated execution.

Enable it with:

```bash
bin/client-worker --worker-index 1 --control-port 4101
```

Key routes:
- `GET /api/runtime`
- `GET /api/runtime/assignments`
- `GET /api/runtime/events`
- `GET /api/runtime/events?stream=true`
- `POST /api/runtime/assignments/execute`

This surface is local tooling only. The server remains the orchestration authority.

## Worker quick start

Run one worker:

```bash
bin/client-worker --worker-index 1
```

Run a second worker:

```bash
bin/client-worker --worker-index 2
```

## Embedded quick start

A direct Elixir embedding flow looks like this conceptually:

```elixir
{:ok, embedded} =
  JidoHiveClient.Embedded.start_link(
    room_id: "room-123",
    participant_id: "alice",
    participant_role: "collaborator",
    api_base_url: "http://127.0.0.1:4000/api"
  )

:ok = JidoHiveClient.Embedded.subscribe(embedded)
{:ok, _contribution} = JidoHiveClient.Embedded.submit_chat(embedded, %{text: "I think Redis is dropping connections"})
snapshot = JidoHiveClient.Embedded.snapshot(embedded)
```

That is the path used by `examples/jido_hive_termui_console`.

## Example TUI consumer

The first real embedded consumer is:
- `../examples/jido_hive_termui_console`

It is built with the local `term_ui` project at:
- `/home/home/p/g/n/term_ui`

The TUI renders:
- a conversation pane from the room timeline
- a context pane from the room context objects
- a chat input that submits through the embedded runtime

## Developer structure

Important areas in this app:
- `lib/jido_hive_client/relay_worker.ex`: relay-connected worker process
- `lib/jido_hive_client/runtime/`: local runtime state and event recording
- `lib/jido_hive_client/boundary/`: protocol and room API boundaries
- `lib/jido_hive_client/embedded.ex`: embeddable runtime for local Elixir consumers
- `lib/jido_hive_client/interceptor.ex`: chat-to-contribution pipeline
- `lib/jido_hive_client/agent_backends/mock.ex`: deterministic backend for tests and UI work
- `lib/jido_hive_client/control/`: local REST and SSE control server

## Raw worker CLI usage

If you need direct control instead of the `bin/` wrappers:

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

## Related docs

- [Repo README](../README.md)
- [Server README](../jido_hive_server/README.md)
- [TUI example README](../examples/jido_hive_termui_console/README.md)
