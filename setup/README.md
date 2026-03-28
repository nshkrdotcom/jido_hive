# Setup Toolkit

`setup/hive` is the user-facing shell wrapper for the operator flow.

It now assumes a generalized worker model:

- generic relay workers instead of fixed role wrappers
- room creation from the currently connected worker set
- optional `--participant-count` locking
- default turn budgets derived from the room execution plan

Run `bin/setup` once from the repo root before using the toolkit.

## Requirements

- `curl`
- `jq`
- a running `jido_hive` server, usually through `bin/server` or
  `bin/live-demo-server`

By default the toolkit talks to `http://127.0.0.1:4000/api`.

You can override that with:

```bash
export JIDO_HIVE_API_BASE=http://127.0.0.1:4100/api
```

Useful defaults:

```bash
export JIDO_HIVE_TENANT_ID=workspace-local
export JIDO_HIVE_ACTOR_ID=operator-1
export JIDO_HIVE_EXEC_CAPABILITY_ID=codex.exec.session
```

## Recommended Demo Flow

Two terminals:

Terminal 1:

```bash
bin/hive-control
```

Terminal 2:

```bash
bin/hive-clients
```

Recommended sequence:

1. In terminal 2, launch two workers from `bin/hive-clients`
2. In terminal 1, choose the live demo option from `bin/hive-control`
3. Watch the client terminal for the per-turn prompt and response previews

## Three-Terminal Local Flow

If you want the direct local flow:

```bash
bin/live-demo-server
bin/client-worker --worker-index 1
bin/client-worker --worker-index 2
```

`bin/live-demo-server` waits for workers, creates or reuses the room, runs the
demo, and prints the room snapshot plus publication plan.

## Core Commands

Show help:

```bash
setup/hive help
```

Wait for the server:

```bash
setup/hive wait-server
```

Wait for workers:

```bash
setup/hive wait-targets --count 2
setup/hive wait-targets --target target-worker-01 --target target-worker-02
```

Create a room from the currently connected workers:

```bash
setup/hive create-room room-manual-1
```

Create a room locked to two workers:

```bash
setup/hive create-room room-manual-1 --participant-count 2
```

Create a room from explicit targets:

```bash
setup/hive create-room room-manual-1 \
  --target target-worker-01 \
  --target target-worker-02
```

Run a room with its locked default budget:

```bash
setup/hive run-room room-manual-1 --turn-timeout-ms 180000
```

Override the number of completed turns to request:

```bash
setup/hive run-room room-manual-1 --max-turns 4 --turn-timeout-ms 180000
```

Run the full live demo:

```bash
setup/hive live-demo --room-id room-demo-1 --participant-count 2
```

If `--participant-count` is omitted, `live-demo` locks all currently connected
compatible workers.

## Important Behavior

- `create-room` and `live-demo` discover connected relay targets from
  `GET /api/targets`
- the room locks the selected worker set at room creation time
- the default turn budget is `participant_count * 3`
- if a worker drops mid-room, the logical budget is preserved and the room keeps
  round-robining across the remaining workers
- `run-room` uses the locked room plan by default when `--max-turns` is omitted

## Publication Commands

Inspect publication planning:

```bash
setup/hive publication-plan room-manual-1
setup/hive publication-runs room-manual-1
```

GitHub only:

```bash
setup/hive publish room-manual-1 \
  --github-connection connection-github-1 \
  --github-repo owner/repo
```

GitHub and Notion together:

```bash
setup/hive publish room-manual-1 \
  --github-connection connection-github-1 \
  --github-repo owner/repo \
  --notion-connection connection-notion-1 \
  --notion-data-source-id data-source-id \
  --notion-title-property Name
```

## Connector Installs

Start and complete a GitHub install:

```bash
setup/hive start-install github --subject octocat --scope repo
setup/hive complete-install <install-id> --subject octocat --scope repo
```

Start and complete a Notion install:

```bash
setup/hive start-install notion --subject notion-workspace
setup/hive complete-install <install-id> --subject notion-workspace
```
