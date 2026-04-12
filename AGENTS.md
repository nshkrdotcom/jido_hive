# AGENTS

## Scope

`jido_hive` is a non-umbrella Elixir monorepo. The active workspace projects are:

- `jido_hive_server`
  Phoenix API, websocket relay, authoritative room engine, persistence,
  publications, and connector state
- `jido_hive_client`
  reusable operator workflows, room-session behavior, and headless JSON CLI
- `jido_hive_surface`
  UI-neutral room and publication workflows over `jido_hive_client`
- `jido_hive_worker_runtime`
  relay workers, assignment execution, worker CLI, and worker-local control API
- `jido_hive_context_graph`
  graph/provenance/workflow projection package; never authoritative room truth
- `jido_hive_switchyard_site`
  Jido Hive site adapter over Switchyard contracts
- `jido_hive_switchyard_tui`
  Jido Hive terminal workflow on the Switchyard runtime
- `jido_hive_web`
  Phoenix LiveView browser UI over the shared surface
- `examples/jido_hive_console`
  runnable composition layer and smoke helper

## Governing Rules

1. `jido_hive_server` owns room truth.
2. `jido_hive_client` owns reusable operator and room-session behavior.
3. `jido_hive_surface` owns reusable UI-neutral room/publication workflows.
4. `jido_hive_worker_runtime` owns relay workers and assignment execution.
5. `jido_hive_context_graph` owns derived graph/provenance projections, not room truth.
6. `jido_hive_switchyard_tui`, `jido_hive_web`, and `examples/jido_hive_console` own rendering, routing, local form/editor/view state, and composition only.

If a room behavior cannot be reproduced from raw HTTP, `jido_hive_client`, or
`jido_hive_surface` as appropriate, the seam is still wrong.

## Read First

Start with these before changing behavior:

- `README.md`
- `docs/architecture.md`
- `docs/debugging_guide.md`
- `setup/README.md`
- `jido_hive_client/README.md`
- `jido_hive_server/README.md`
- `jido_hive_surface/README.md`
- `jido_hive_worker_runtime/README.md`
- `jido_hive_web/README.md` when touching browser UI
- `jido_hive_switchyard_tui/README.md` and `examples/jido_hive_console/README.md` when touching TUI or console behavior

Also read the nearest package-local `AGENTS.md` before editing inside:

- `jido_hive_server/AGENTS.md`
- `jido_hive_web/AGENTS.md`

Deep-dive notes may live under `~/jb/docs/...`, but repo docs must stay
self-contained and must not use absolute filesystem paths.

## Setup

From repo root:

```bash
bin/setup
```

## Local Runtime

Normal local stack:

```bash
bin/live-demo-server
bin/client-worker --worker-index 1
bin/client-worker --worker-index 2
```

Recommended operator flow:

```bash
bin/hive-control
bin/hive-clients
```

Useful commands:

- `setup/hive help`
- `setup/hive doctor`
- `setup/hive server-info`
- `setup/hive targets`
- `setup/hive live-demo --participant-count 2`
- `bin/hive-control --prod`
- `bin/hive-clients --prod`

## Debugging Order

Always debug in this order:

1. server truth
2. headless `jido_hive_client`
3. shared `jido_hive_surface` when the behavior is workflow/UI-adjacent
4. `jido_hive_worker_runtime` if the issue involves target registration, relay, or assignment execution
5. `jido_hive_switchyard_tui`, `jido_hive_web`, or `examples/jido_hive_console` last

Representative checks:

```bash
setup/hive server-info
curl -sS http://127.0.0.1:4000/api/rooms/<room-id> | jq
curl -sS http://127.0.0.1:4000/api/rooms/<room-id>/events | jq

cd jido_hive_client
mix escript.build
./jido_hive_client room show --api-base-url http://127.0.0.1:4000/api --room-id <room-id> | jq
./jido_hive_client room workflow --api-base-url http://127.0.0.1:4000/api --room-id <room-id> | jq
./jido_hive_client room tail --api-base-url http://127.0.0.1:4000/api --room-id <room-id> | jq
```

If it reproduces from raw HTTP, `jido_hive_client`, or `jido_hive_surface`, it
is not a UI-only bug.

## Structured Trace

For bash-first debugging, prefer:

```bash
cd jido_hive_client
JIDO_HIVE_CLIENT_LOG_LEVEL=debug \
./jido_hive_client room show --api-base-url http://127.0.0.1:4000/api --room-id <room-id> \
  > room.json \
  2> trace.ndjson
```

Rules:

- JSON stays on stdout
- trace stays on stderr
- capture this before adding ad hoc logging

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

Worker runtime:

```bash
cd jido_hive_worker_runtime
iex -S mix
```

Do not assume production remote shell attach exists as a supported workflow.
For production, prefer HTTP, headless client commands, and platform logs.

## Package Boundaries

When changing behavior:

- keep server-owned workflow truth, validation, and persistence in `jido_hive_server`
- keep reusable operator/session behavior in `jido_hive_client`
- keep reusable room/publication orchestration in `jido_hive_surface`
- keep worker join, assignment execution, and worker-local state in `jido_hive_worker_runtime`
- keep graph/provenance derivation in `jido_hive_context_graph`
- keep TUI/web/example packages free of business logic that cannot be reproduced headlessly

Specific guardrails:

- if a feature is needed by both web and TUI, prefer `jido_hive_surface`
- if a room behavior cannot be reproduced from the headless client, do not hide it in a UI package
- `jido_hive_web` must not bypass the shared operator seam to reach into server internals
- `jido_hive_switchyard_tui` owns terminal workflow state, not server truth
- `examples/jido_hive_console` stays a thin composition layer

## Connector Tokens

Validated manual-install token names:

- GitHub: `GITHUB_TOKEN`
- Notion: `NOTION_TOKEN`

Do not default to `GITHUB_OAUTH_ACCESS_TOKEN` or
`NOTION_OAUTH_ACCESS_TOKEN` for manual install completion.

## CI and Quality

Run repo-wide checks from repo root:

```bash
mix ci
```

Alias flow:

1. `mix monorepo.deps.get`
2. `mix monorepo.format --check-formatted`
3. `mix monorepo.compile`
4. `mix monorepo.test`
5. `mix monorepo.credo --strict`
6. `mix monorepo.dialyzer`
7. `mix monorepo.docs`

Shortcuts:

- `mix mr.deps.get`
- `mix mr.format`
- `mix mr.compile`
- `mix mr.test`
- `mix mr.credo`
- `mix mr.dialyzer`
- `mix mr.docs`

Root workspace prefers local `../blitz`; otherwise it falls back to Hex
`~> 0.1.0`.

## Documentation Rules

- Repo docs must use repo-relative links and paths.
- Do not put absolute filesystem paths in repo docs.
- Put machine-specific investigation notes under `~/jb/docs/...`, not in repo
  READMEs.

## Deployment

Coolify tasks run through `coolify_ex 0.5.1` in `jido_hive_server` under
`MIX_ENV=coolify`:

```bash
scripts/deploy_coolify.sh
cd jido_hive_server
MIX_ENV=coolify mix coolify.latest --project server
MIX_ENV=coolify mix coolify.status --project server --latest
```

## Endpoints

- local API: `http://127.0.0.1:4000/api`
- local websocket: `ws://127.0.0.1:4000/socket/websocket`
- local web UI: `http://127.0.0.1:4100/rooms`
- production API: `https://jido-hive-server-test.app.nsai.online/api`
- production websocket: `wss://jido-hive-server-test.app.nsai.online/socket/websocket`
