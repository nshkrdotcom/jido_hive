# jido_hive

`jido_hive` is a Phoenix coordination server plus local ASM-backed worker
clients.

This repo has two Mix apps:

- `jido_hive_server`: the Phoenix API and relay websocket
- `jido_hive_client`: the local executor used by the client wrappers

The current demo is a generalized multi-worker round-robin slice:

- 1 to 39 connected workers
- the coordinator still chooses the turn role for each job
- the room locks the selected worker set when the room is created
- the default turn budget is `participant_count * 3`

That means:

- 1 worker -> 3 planned turns
- 2 workers -> 6 planned turns
- 39 workers -> 117 planned turns

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
bin/client-worker --worker-index 1
```

Terminal 3:

```bash
bin/client-worker --worker-index 2
```

That is the quickest way to see the coordinator distribute work across more than
one worker with a locked round-robin plan.

## Two-Terminal Menus

For the main operator flow, use:

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

Recommended two-terminal loop:

1. In terminal 2, run `bin/hive-clients` and choose `2` for two workers, or
   choose `3` for a custom worker count.
2. In terminal 1, run `bin/hive-control` and choose `3`.
3. Watch terminal 2 for `system prompt preview`, `user prompt preview`,
   `response preview`, `completed`, and `result published` lines.

`bin/hive-clients` can launch 1, 2, or a custom 1..39 worker fan-out in one
terminal. If the room is created from all connected workers, the locked plan
budget defaults to `worker_count * 3`.

## What The Demo Does

The current slice is intentionally simple but now generalized:

- workers connect outbound and register relay targets
- `setup/hive create-room` or `live-demo` locks the selected worker set
- the coordinator schedules workers in round-robin order
- the coordinator assigns the current stage role:
  - `proposer`
  - `critic`
  - `resolver`
- workers execute locally through `Jido.Harness -> asm -> ASM`
- the server persists room state, disputes, execution metadata, and publication
  plans in SQLite

This is still a coordinator-driven demo, not a peer-to-peer multi-agent system.
The generalization is about distributed workload across generic workers, not
about removing the coordinator.

## Local Commands

These are the main repo-level commands:

```bash
bin/setup
bin/hive-control
bin/hive-clients
bin/client-worker --worker-index 1
setup/hive help
```

Legacy wrappers still exist:

```bash
bin/client-architect
bin/client-skeptic
```

They remain available for compatibility, but the generic worker wrappers and the
menu flow are now the primary path.

## Production

The deployed public server is:

- HTTPS: `https://jido-hive-server-test.app.nsai.online`
- API base: `https://jido-hive-server-test.app.nsai.online/api`
- WebSocket relay: `wss://jido-hive-server-test.app.nsai.online/socket/websocket`

Workers alone do not start LLM activity. They only connect, register targets,
and wait for `job.start`.

To exercise the production demo:

```bash
bin/hive-clients --prod
bin/hive-control --prod
```

Or manually:

```bash
bin/client-worker --prod --worker-index 1
bin/client-worker --prod --worker-index 2
setup/hive --prod live-demo --participant-count 2
```

Useful production checks:

```bash
setup/hive --prod doctor
setup/hive --prod targets
setup/hive --prod server-info
```

## Manual Room Control

The setup toolkit is the main shell surface for manual control:

```bash
setup/hive wait-server
setup/hive wait-targets --count 2
setup/hive create-room room-manual-1 --participant-count 2
setup/hive run-room room-manual-1 --turn-timeout-ms 180000
setup/hive publication-plan room-manual-1
setup/hive publication-runs room-manual-1
```

Important behavior:

- `doctor` verifies the deployed root demo contract in addition to API
  reachability
- `server-info` is the scripted replacement for ad hoc `curl` checks against the
  root JSON status payload
- `create-room` locks either all currently connected compatible workers or the
  requested `--participant-count` subset
- `run-room` uses the locked execution plan by default when `--max-turns` is
  omitted
- `live-demo` waits for workers, creates or reuses the room, runs it, and prints
  the room snapshot plus publication plan

The toolkit is documented in [setup/README.md](setup/README.md).

## Drop-Off Behavior

The room budget is logical, not just a count of raw attempts.

If a room starts with 10 workers, the default planned budget is 30 completed
turns. If one worker drops after the room starts:

- the room preserves the 30-turn plan
- the abandoned worker is excluded for the rest of that room
- the remaining workers continue absorbing the rest of the round robin

Late results from abandoned turns are ignored.

## Documentation

High-level docs:

- [Architecture](docs/architecture.md)
- [Developer Guide: Multi-Agent Round Robin](docs/developer/multi_agent_round_robin.md)
- [Setup Toolkit](setup/README.md)

The generated server docs now expose a dedicated Developer Guides section through
`jido_hive_server/mix.exs`.

## Deploy And Logs

Deployments use `coolify_ex` from inside `jido_hive_server`, with the repo-root
manifest at `.coolify_ex.exs`.

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

Useful nested-app commands:

```bash
cd jido_hive_server
MIX_ENV=dev mix coolify.latest --project server
MIX_ENV=dev mix coolify.status --project server --latest
MIX_ENV=dev mix coolify.logs --project server --latest --tail 200
MIX_ENV=dev mix coolify.app_logs --project server --lines 200 --follow
```

## GitHub And Notion Publishing

The setup toolkit also wraps the live connector flow.

Start and complete installs:

```bash
setup/hive start-install github --subject octocat --scope repo
setup/hive complete-install <install-id> --subject octocat --scope repo
setup/hive start-install notion --subject notion-workspace
setup/hive complete-install <install-id> --subject notion-workspace
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
