# AGENTS

## Scope

This repo has two Mix apps:

- `jido_hive_server` – Phoenix API and websocket relay
- `jido_hive_client` – local executor wrappers

## Setup

```bash
bin/setup
```

## Local Runtime

```bash
bin/live-demo-server
bin/client-worker --worker-index 1
bin/client-worker --worker-index 2
```

`bin/hive-control` + `bin/hive-clients` are the recommended operator flow:

```bash
bin/hive-control
bin/hive-clients
```

## Useful Runtime Commands

- `bin/hive-clients --prod` / `bin/hive-control --prod`
- `setup/hive --prod live-demo --participant-count 2`
- `setup/hive --prod doctor`
- `setup/hive --prod server-info`
- `setup/hive --prod targets`
- `setup/hive help`

## CI & Quality (Root Workspace)

Run repo-wide checks from repo root with:

```bash
mix ci
```

Alias flow:

1. `mix deps.get`
2. `mix format --check-formatted`
3. `mix compile`
4. `mix test`
5. `mix credo --strict`
6. `mix dialyzer`
7. `mix docs`

Monorepo task aliases:

- `mix monorepo.deps.get`
- `mix monorepo.format`
- `mix monorepo.compile`
- `mix monorepo.test`
- `mix monorepo.credo`
- `mix monorepo.dialyzer`
- `mix monorepo.docs`

Shortcuts:

- `mix mr.deps.get`
- `mix mr.format`
- `mix mr.compile`
- `mix mr.test`
- `mix mr.credo`
- `mix mr.dialyzer`
- `mix mr.docs`

Root workspace prefers local `../blitz`; if not present, it uses Hex `~> 0.1.0`.

## Deployment Notes

Coolify tasks run through the server app in `MIX_ENV=coolify`:

```bash
scripts/deploy_coolify.sh
cd jido_hive_server
MIX_ENV=coolify mix coolify.latest --project server
MIX_ENV=coolify mix coolify.status --project server --latest
```

## Endpoint Reference

- Local API: `http://127.0.0.1:4000/api`
- Local WebSocket: `ws://127.0.0.1:4000/socket/websocket`
- Production base API: `https://jido-hive-server-test.app.nsai.online/api`
- Production WebSocket: `wss://jido-hive-server-test.app.nsai.online/socket/websocket`
