# jido_hive

`jido_hive` is a Phoenix coordination server plus local ASM-backed clients.

This repo has two Mix apps:

- `jido_hive_server`: the Phoenix API and relay websocket
- `jido_hive_client`: the local executor used by the client wrappers

If you only want the main happy path, do this:

```bash
bin/setup
bin/live-demo-server
bin/client-architect
bin/client-skeptic
```

That is the fastest way to see the current collaboration loop working.

## Two-Terminal Menus

If you want a simpler operator flow, use these two menu scripts:

Terminal 1:

```bash
bin/hive-control
```

Terminal 2:

```bash
bin/hive-clients
```

For production, use:

Terminal 1:

```bash
bin/hive-control --prod
```

Terminal 2:

```bash
bin/hive-clients --prod
```

`bin/hive-control` is the control/menu side for server checks, room runs,
Coolify deploys, and prod log tails. `bin/hive-clients` is the client/menu side
for architect, skeptic, or both clients in one terminal.

Fastest two-terminal loop:

1. In terminal 2, run `bin/hive-clients` or `bin/hive-clients --prod`, then
   choose `3`.
2. In terminal 1, run `bin/hive-control` or `bin/hive-control --prod`, then
   choose `3`.
3. Watch terminal 2 for `system prompt preview`, `user prompt preview`,
   `response preview`, `completed`, and `result published` lines.

## What This Does

The current slice is a real client-server collaboration loop:

- local clients connect outbound and register relay targets
- the server opens refereed turns and sends a versioned collaboration envelope
- clients execute locally through `Jido.Harness -> asm -> ASM`
- the server persists room snapshots and publication runs in SQLite
- GitHub and Notion publication planning and execution go through
  `Jido.Integration.V2`

## Requirements

- Erlang/OTP 28
- Elixir `~> 1.19`
- a working local AI CLI for live runs, such as Codex CLI
- `curl` and `jq` for the setup toolkit

## Fastest Local Run

From a fresh clone:

```bash
git clone <repo>
cd jido_hive
bin/setup
```

Then open three terminals.

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

What you should see:

- the server waits for both local targets
- it creates a room and runs the refereed slice
- clients receive turns and execute locally
- the server prints the final room snapshot and publication plan

Notes:

- `bin/live-demo-server` sets the Phoenix log level to `info` so you see room
  and dispatch progress instead of noisy dev query spam
- if you want the older wrapper, `bin/demo-first-slice` delegates to
  `setup/hive live-demo`
- for live AI runs, `bin/live-demo-server` and `bin/demo-first-slice` honor
  `ROOM_ID`, `JIDO_HIVE_TURN_TIMEOUT_MS`, and `JIDO_HIVE_WAIT_TIMEOUT_MS`

## Public App

The deployed public server is:

- HTTPS: `https://jido-hive-server-test.app.nsai.online`
- API base: `https://jido-hive-server-test.app.nsai.online/api`
- WebSocket relay: `wss://jido-hive-server-test.app.nsai.online/socket/websocket`

Production browser visits land on the human-friendly root page instead of a raw
JSON 404.

## Run Against Prod

Repo helpers stay local by default and opt into the deployed server with
explicit `--prod` flags:

```bash
bin/client-architect --prod
bin/client-skeptic --prod
setup/hive --prod doctor
setup/hive --prod targets
```

What those commands do:

- `bin/client-architect --prod` and `bin/client-skeptic --prod` connect to the
  production websocket, register their targets, and then wait for relay work
- on a healthy connection the client prints the actual `url=...` and then a
  `ready ... waiting_for=job.start` line
- those client commands alone do not create any LLM traffic; they only bring
  the remote participants online

To make the prod clients actually do work, start a room or live demo:

```bash
setup/hive --prod live-demo
```

Or use the two-menu flow:

1. Terminal 2: `bin/hive-clients --prod`, then choose `3`
2. Terminal 1: `bin/hive-control --prod`, then choose `3`
3. Watch terminal 2 for the per-turn prompt and response previews

Or drive it manually:

```bash
setup/hive --prod create-room room-prod-1
setup/hive --prod run-room room-prod-1 --turn-timeout-ms 180000
```

If you are integrating outside the repo helpers, use these URLs directly:

- API base: `https://jido-hive-server-test.app.nsai.online/api`
- WebSocket: `wss://jido-hive-server-test.app.nsai.online/socket/websocket`
- `GET /api/targets` lists connected relay targets
- `POST /api/rooms` creates a collaboration room
- `GET /api/rooms/:id` fetches room state
- `POST /api/rooms/:id/run` now returns the room snapshot even when a turn
  fails, so the failure details stay visible instead of collapsing to a blind
  `422 turn_failed`

## Common Local Commands

These are the main operator commands when you want to drive the flow manually:

```bash
setup/hive help
setup/hive doctor
setup/hive wait-server
setup/hive wait-targets
setup/hive create-room room-manual-1
setup/hive run-room room-manual-1 --turn-timeout-ms 180000
setup/hive publication-plan room-manual-1
```

The setup toolkit is documented in [setup/README.md](setup/README.md).

## Deploy And Watch Logs

Deployments use `coolify_ex` from inside `jido_hive_server`, with the
repo-root manifest at `.coolify_ex.exs`.

When this repo is checked out beside `../coolify_ex`, the nested app uses that
local path automatically during development; otherwise it falls back to the Hex
release.

From the repo root:

```bash
export COOLIFY_BASE_URL="https://coolify.example.com"
export COOLIFY_TOKEN="..."
export COOLIFY_APP_UUID="..."
scripts/deploy_coolify.sh
```

Useful deploy variants:

```bash
scripts/deploy_coolify.sh --no-push
scripts/deploy_coolify.sh --project server
scripts/deploy_coolify.sh --force --instant
scripts/deploy_coolify.sh --skip-verify
```

The wrapper just runs the real Mix task from the nested app:

```bash
cd jido_hive_server
MIX_ENV=dev mix coolify.deploy
```

The full project-based inspection flow is:

```bash
cd jido_hive_server
MIX_ENV=dev mix coolify.latest --project server
MIX_ENV=dev mix coolify.logs --project server --latest --tail 200
MIX_ENV=dev mix coolify.app_logs --project server --lines 200 --follow
```

If you need status for the latest deployment without spelling out the UUID:

```bash
cd jido_hive_server
MIX_ENV=dev mix coolify.status --project server --latest
```

Runtime Phoenix logs still come from `coolify.app_logs`; deployment/build logs
come from `coolify.logs`.

`coolify_ex` discovers `.coolify_ex.exs` by walking parent directories, so the
nested `jido_hive_server` project can use the repo-root manifest without an
explicit `--config` path.

## GitHub And Notion Publishing

The setup toolkit also wraps the live connector flow.

Start a GitHub install:

```bash
setup/hive start-install github --subject octocat --scope repo
```

Complete that install after exchanging the provider code or token upstream:

```bash
setup/hive complete-install <install-id> --subject octocat --scope repo
```

List current connector connections:

```bash
setup/hive connections github
setup/hive connections notion
```

Execute a publication run:

```bash
setup/hive publish room-manual-1 \
  --github-connection connection-github-1 \
  --github-repo owner/repo \
  --notion-connection connection-notion-1 \
  --notion-data-source-id data-source-id \
  --notion-title-property Name
```

Inspect durable publication history:

```bash
setup/hive publication-runs room-manual-1
```

If you already have live connector connections, `bin/live-demo-server` can also
publish automatically when these env vars are set:

- `JIDO_HIVE_GITHUB_CONNECTION`
- `JIDO_HIVE_GITHUB_REPO`
- `JIDO_HIVE_NOTION_CONNECTION`
- `JIDO_HIVE_NOTION_DATA_SOURCE_ID`
- `JIDO_HIVE_NOTION_TITLE_PROPERTY`
- `JIDO_HIVE_AUTO_PUBLISH=1`

## Useful Client Env Vars

The repo-level `bin/client` wrapper accepts these useful env vars:

- `JIDO_HIVE_URL`
- `JIDO_HIVE_WORKSPACE_ID`
- `JIDO_HIVE_RELAY_TOPIC`
- `JIDO_HIVE_WORKSPACE_ROOT`
- `PARTICIPANT_ROLE`
- `PARTICIPANT_ID`
- `TARGET_ID`
- `USER_ID`
- `CAPABILITY_ID`
- `JIDO_HIVE_PROVIDER`
- `JIDO_HIVE_MODEL`
- `JIDO_HIVE_REASONING_EFFORT`
- `JIDO_HIVE_TIMEOUT_MS`
- `JIDO_HIVE_CLI_PATH`
- `JIDO_HIVE_TURN_TIMEOUT_MS`

## Behavior Notes

- live provider turns can finish as `publication_ready` or `in_review`
  depending on whether the model emits a `PUBLISH` action
- the client performs one strict no-tool repair pass when a provider returns
  prose or malformed JSON instead of the room contract
- the default Codex runtime profile is `gpt-5.4` with `low` reasoning unless
  you override `JIDO_HIVE_MODEL` or `JIDO_HIVE_REASONING_EFFORT`
