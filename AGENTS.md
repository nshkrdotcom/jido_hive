# AGENTS

## Scope

This repo has three relevant Mix apps:

- `jido_hive_server` – Phoenix API and websocket relay
- `jido_hive_client` – reusable operator/session client and worker runtime
- `examples/jido_hive_console` – ExRatatui operator console built on `jido_hive_client`

Architecture rule:

1. `jido_hive_server` owns room truth.
2. `jido_hive_client` owns reusable operator and room-session behavior.
3. the ExRatatui console owns only rendering, input, and screen-local view state.

If a room behavior cannot be reproduced from the headless client, the seam is still wrong.

## Required Reading

Start here before changing behavior:

- `README.md`
- `docs/debugging_guide.md`
- `jido_hive_client/README.md`
- `jido_hive_server/README.md`
- `examples/jido_hive_console/README.md`

Additional deep-dive docs live outside the repo under `~/jb/docs/...`. Repo docs must stay self-contained and must not use absolute filesystem paths.

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
- `setup/hive --prod connections github --subject alice`
- `setup/hive --prod connections notion --subject alice`
- `setup/hive help`

## Debugging Order

Always debug in this order:

1. server truth first
2. headless `jido_hive_client` second
3. TUI last

That means:

```bash
setup/hive --prod server-info
curl -sS https://jido-hive-server-test.app.nsai.online/api/rooms/<room-id>
curl -sS https://jido-hive-server-test.app.nsai.online/api/rooms/<room-id>/timeline
```

Then reproduce without the TUI:

```bash
cd jido_hive_client
mix escript.build

./jido_hive_client room show --api-base-url https://jido-hive-server-test.app.nsai.online/api --room-id <room-id>
./jido_hive_client room tail --api-base-url https://jido-hive-server-test.app.nsai.online/api --room-id <room-id>
./jido_hive_client room submit --api-base-url https://jido-hive-server-test.app.nsai.online/api --room-id <room-id> --participant-id alice --text "debug probe"
./jido_hive_client room run --api-base-url https://jido-hive-server-test.app.nsai.online/api --room-id <room-id> --max-assignments 1 --assignment-timeout-ms 60000
./jido_hive_client room run-status --api-base-url https://jido-hive-server-test.app.nsai.online/api --room-id <room-id> --operation-id <operation-id>
```

If it reproduces headlessly, it is not a TUI-only bug.

Full guide:

- `docs/debugging_guide.md`

## Structured Trace

For bash-first debugging, prefer:

```bash
cd jido_hive_client
JIDO_HIVE_CLIENT_LOG_LEVEL=debug \
./jido_hive_client room show --api-base-url https://jido-hive-server-test.app.nsai.online/api --room-id <room-id> \
  > room.json \
  2> trace.ndjson
```

Rules:

- JSON stays on stdout.
- trace goes to stderr.
- use this before adding more ad hoc logging.

## Local `iex`

Use local `iex` when bash-level reproduction is not enough.

Server:

```bash
cd jido_hive_server
iex -S mix phx.server
```

Client:

```bash
cd jido_hive_client
iex -S mix
```

Do not assume production remote shell attach exists as a supported workflow. For production, prefer HTTP, headless client commands, and Coolify logs.

## Console-Specific Notes

The console should own only:

- current route and screen
- focus and selection
- draft buffers
- wizard and publish form state
- help/debug overlay visibility
- transient banners/status copy

The console should not own:

- authoritative room truth
- transport logic
- connector truth
- business behavior that does not also exist headlessly

If a console bug appears, reproduce it headlessly first. Only debug the ExRatatui layer after the server and headless client are understood.

## Connector Install Tokens

Validated manual-install tokens:

- GitHub: `GITHUB_TOKEN`
- Notion: `NOTION_TOKEN`

Do not default to `GITHUB_OAUTH_ACCESS_TOKEN` or `NOTION_OAUTH_ACCESS_TOKEN` for manual install completion.

## CI & Quality (Root Workspace)

Run repo-wide checks from repo root with:

```bash
mix ci
```

Alias flow:

1. `mix deps.get`
2. `mix format --check-formatted`
3. `mix compile --warnings-as-errors`
4. `mix test`
5. `mix credo --strict`
6. `mix dialyzer --force-check`
7. `mix docs --warnings-as-errors`

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

## Documentation Rules

- Repo docs must use repo-relative links and paths.
- Do not put absolute filesystem paths in repo docs.
- If you need richer investigation notes or local-machine-specific paths, put them under `~/jb/docs/...`, not in repo `README.md` files.

## Deployment Notes

Coolify tasks run through `coolify_ex 0.5.1` in the server app under `MIX_ENV=coolify`:

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
