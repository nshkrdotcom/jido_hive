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
bin/client-architect
```

Terminal 3:

```bash
bin/client-skeptic
```

This runs the server locally and connects both local clients to the local
websocket.

## Two-Terminal Menus

For a simpler workflow, use:

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

Fastest two-terminal flow:

1. Terminal 2: run `bin/hive-clients` or `bin/hive-clients --prod`, then
   choose `3`
2. Terminal 1: run `bin/hive-control` or `bin/hive-control --prod`, then
   choose `3`
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

## Run Clients Locally

From the repo root:

```bash
bin/client-architect
bin/client-skeptic
```

These default to the local server.

## Run Clients Against Production

From the repo root:

```bash
bin/client-architect --prod
bin/client-skeptic --prod
```

Production API and websocket:

- API: `https://jido-hive-server-test.app.nsai.online/api`
- WebSocket: `wss://jido-hive-server-test.app.nsai.online/socket/websocket`

Important:

- `--prod` clients connect and register targets, then wait for work
- a healthy client prints `url=...` and then `ready ... waiting_for=job.start`
- the clients alone do not start LLM activity

To make the prod clients actually do work:

```bash
setup/hive --prod live-demo
```

The menu equivalent is:

1. Terminal 2: `bin/hive-clients --prod`, then choose `3`
2. Terminal 1: `bin/hive-control --prod`, then choose `3`
3. The client terminal shows the prompt/response previews for each turn

Or manually:

```bash
setup/hive --prod create-room room-prod-1
setup/hive --prod run-room room-prod-1 --turn-timeout-ms 180000
```

Useful prod checks:

```bash
setup/hive --prod doctor
setup/hive --prod targets
```

## Coolify

This repo uses `coolify_ex` from inside `jido_hive_server`. The manifest lives
at the repo root in `.coolify_ex.exs`.

During local workspace development, `jido_hive_server` prefers a sibling
`../coolify_ex` checkout automatically and falls back to the Hex release
outside that workspace layout.

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
MIX_ENV=dev mix coolify.deploy
```

Latest deployment summary for the manifest project:

```bash
cd jido_hive_server
MIX_ENV=dev mix coolify.latest --project server
```

Deployment status for the latest deployment:

```bash
cd jido_hive_server
MIX_ENV=dev mix coolify.status --project server --latest
```

Deployment logs for the latest deployment:

```bash
cd jido_hive_server
MIX_ENV=dev mix coolify.logs --project server --latest --tail 200
```

Runtime Phoenix logs for the live Coolify-managed app:

```bash
cd jido_hive_server
MIX_ENV=dev mix coolify.app_logs --project server --lines 200 --follow
```

Use `coolify.logs` for deployment/build logs and `coolify.app_logs` for runtime
Phoenix logs.

Room runs now return the room snapshot even when a turn fails, so you can fetch
the failed turn execution details instead of only seeing `422 turn_failed`.
