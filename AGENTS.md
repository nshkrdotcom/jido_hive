# AGENTS

This repo has two main apps:

- `jido_hive_server`: Phoenix API and relay websocket
- `jido_hive_client`: local executor used by the client wrappers

## Fastest Local Run

From the repo root:

```bash
bin/setup
```

Open three terminals.

Terminal 1:

```bash
bin/live-demo-server
```

Terminal 2:

```bash
bin/client-worker --worker-index 1
```

Terminal 3:

```bash
bin/client-worker --worker-index 2
```

This runs the server locally and connects two generic workers to the local
websocket.

## Two-Terminal Menus

For the main operator flow:

Terminal 1:

```bash
bin/hive-control
```

Terminal 2:

```bash
bin/hive-clients
```

For production:

Terminal 1:

```bash
bin/hive-control --prod
```

Terminal 2:

```bash
bin/hive-clients --prod
```

Recommended two-terminal flow:

1. Terminal 2: run `bin/hive-clients` or `bin/hive-clients --prod`, then choose
   `2` for a two-worker demo or `3` for a custom worker count
2. Terminal 1: run `bin/hive-control` or `bin/hive-control --prod`, then choose
   `3`
3. Watch terminal 2 for `system prompt preview`, `user prompt preview`,
   `response preview`, `completed`, and `result published`

## Run The Server Locally

Canonical local server command:

```bash
bin/live-demo-server
```

If you want to work directly from the nested app instead:

```bash
cd jido_hive_server
mix deps.get
mix phx.server
```

Local API and websocket:

- API: `http://127.0.0.1:4000/api`
- WebSocket: `ws://127.0.0.1:4000/socket/websocket`

## Run Workers Locally

From the repo root:

```bash
bin/client-worker --worker-index 1
bin/client-worker --worker-index 2
```

These default to the local server.

## Run Workers Against Production

From the repo root:

```bash
bin/client-worker --prod --worker-index 1
bin/client-worker --prod --worker-index 2
```

Production API and websocket:

- API: `https://jido-hive-server-test.app.nsai.online/api`
- WebSocket: `wss://jido-hive-server-test.app.nsai.online/socket/websocket`

Important:

- `--prod` workers connect and register targets, then wait for work
- a healthy worker prints `url=...` and then `ready ... waiting_for=job.start`
- the workers alone do not start LLM activity

To make the prod workers actually do work:

```bash
setup/hive --prod live-demo --participant-count 2
```

Useful prod checks:

```bash
setup/hive --prod doctor
setup/hive --prod server-info
setup/hive --prod targets
```

`doctor` now verifies both API reachability and the deployed root demo contract
before printing targets.

## Coolify

This repo uses `coolify_ex` from inside `jido_hive_server`. The manifest lives
at the repo root in `.coolify_ex.exs`. Coolify tasks run in the dedicated
`MIX_ENV=coolify` lane so deploy-only tooling does not affect the normal
dev/test/docs quality floor.

Canonical deploy from this repo:

```bash
scripts/deploy_coolify.sh
```

Required env vars:

- `COOLIFY_BASE_URL`
- `COOLIFY_TOKEN`
- `COOLIFY_APP_UUID`

Direct `mix` usage from the nested app:

```bash
cd jido_hive_server
MIX_ENV=coolify mix coolify.deploy
```

Useful inspection commands:

```bash
cd jido_hive_server
MIX_ENV=coolify mix coolify.latest --project server
MIX_ENV=coolify mix coolify.status --project server --latest
MIX_ENV=coolify mix coolify.logs --project server --latest --tail 200
MIX_ENV=coolify mix coolify.app_logs --project server --lines 200 --follow
```

Room runs now return the room snapshot even when a turn fails, so you can fetch
the failed turn execution details instead of only seeing `422 turn_failed`.
