# JidoHiveClient: The Participant Runtime

`jido_hive_client` is the execution node for the `jido_hive` participation substrate.

The client acts as a **Participant Runtime**. It does not own the room state, it does not decide what workflow to execute, and it does not coordinate directly with other workers. Its sole responsibility is to:

1. Declare its capabilities to the server.
2. Receive a scoped **Context View**.
3. Execute locally (e.g., via LLMs) to fulfill a strictly defined **Contribution Contract**.
4. Return typed **Context Objects** with fulfilled provenance headers.

If you are new to the architecture, read the top-level concepts in [../README.md](../README.md).

## The Execution Model

The client architecture reflects the substrate's shift away from monolithic prompts towards structured, contracted execution.

When the server dispatches a turn to this worker, the worker receives an `assignment.start` payload containing:
- `context_view`: A filtered, structured view of the room. It contains the brief, active rules, recent contributions, and relevant `context_objects`. The worker only sees what the server's dispatch policy allows it to see.
- `contribution_contract`: A strict requirement of what must be produced. It defines `allowed_contribution_types` (e.g., reasoning vs. execution), `allowed_object_types` (e.g., belief, note, artifact), and relation constraints.

The client then:
1. Normalizes the contract (`ProtocolCodec`).
2. Generates a prompt ensuring the LLM understands the schema requirements (`CollaborationPrompt`).
3. Executes the LLM call locally (`Jido.Harness -> asm`).
4. Attempts to automatically repair the output if the LLM returns unstructured prose instead of JSON (`RepairPolicy`).
5. Decodes and submits the final `contribution.submit` payload back to the server over the relay.

## Quick Start

Run a worker connected to the local development server:
```bash
bin/client-worker --worker-index 1
```

Run a second worker:
```bash
bin/client-worker --worker-index 2
```

These wrappers set up standard capabilities (e.g., `codex.exec.session`), target identities, and LLM provider defaults.

## Local Control API

While the server is the orchestration authority, the client can optionally run a local `REST + SSE` control surface. This API is designed for local diagnostics, node-health dashboards, and **manual, isolated execution testing**.

To enable it, pass `--control-port`:
```bash
bin/client-worker --worker-index 1 --control-port 4101
```

### Key Local Routes

- `GET /api/runtime`: View the current ephemeral snapshot of the worker (connection status, metrics).
- `GET /api/runtime/assignments`: View the history of local assignments handled by this node.
- `GET /api/runtime/events?stream=true`: SSE stream of local execution events.
- **`POST /api/runtime/assignments/execute`**: A highly useful developer hook. You can `POST` a raw assignment payload directly to the worker to test its LLM execution, decoding, and repair logic *without* needing a server or room setup.

Example testing execution directly:
```bash
curl -X POST http://127.0.0.1:4101/api/runtime/assignments/execute \
  -H 'Content-Type: application/json' \
  -d '{
        "assignment": {
          "assignment_id": "test-1",
          "objective": "Summarize the rules.",
          "phase": "analysis",
          "context_view": { "rules": ["Must return JSON"] },
          "contribution_contract": { "allowed_contribution_types": ["reasoning"], "allowed_object_types": ["note"] }
        }
      }'
```

## Raw CLI Usage

If you need fine-grained control over participant capabilities and provider settings without using the `bin/` wrappers:

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

## Developer Guidance

The client is highly decoupled:
- **`lib/jido_hive_client/boundary/`**: The Protocol Codec translates between canonical JSON maps and internal Elixir structs.
- **`lib/jido_hive_client/executor/`**: Handles the entire assignment lifecycle: building the session, generating the prompt, repairing faulty outputs, and projecting the result into a valid contribution.
- **`lib/jido_hive_client/runtime/`**: An ephemeral `gen_server` state machine holding local observability data.
- **`lib/jido_hive_client/control/`**: The local REST API (Bandit/Plug).

This design allows you to easily plug in different `Jido` execution backends or target environments by swapping out the core `Executor` logic without rewriting the relay communication layer.