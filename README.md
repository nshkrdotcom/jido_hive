# jido_hive

`jido_hive` is a non-umbrella monorepo with two separate Mix apps:

- `jido_hive_server`: Phoenix coordination server
- `jido_hive_client`: local ASM-backed executor

The current slice is a real client-server collaboration loop:

- local clients connect outbound and advertise session targets
- the server opens refereed turns and sends a versioned collaboration envelope
- clients execute locally through `Jido.Harness -> asm -> ASM`
- the server persists room snapshots, disputes, and publication runs in SQLite
- GitHub and Notion publication planning and execution go through
  `Jido.Integration.V2`

## Requirements

- Erlang/OTP 28
- Elixir `~> 1.19`
- a working local AI CLI for live runs, such as Codex CLI
- `curl` and `jq` for the setup toolkit

## Fresh Machine

From a fresh clone, start at the repo root:

```bash
git clone <repo>
cd jido_hive
bin/setup
```

That bootstrap does the first-run work for both nested Mix apps:

- installs Hex and Rebar if needed
- runs `mix setup` in `jido_hive_server`
- runs `mix setup` in `jido_hive_client`
- prints the next local run commands

If you only want to check the local toolchain first:

```bash
bin/setup --check
```

## Quick Start

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

The server wrapper will:

1. wait for both local targets
2. create a room
3. run the refereed slice
4. print the final room snapshot
5. print the publication plan

The room id is printed in the server terminal when it starts.

The client terminals now announce when they:

- connect and register their targets
- receive a turn
- start provider execution through `Jido.Harness -> asm -> ASM`
- complete a turn and publish the result back to the server

The live-demo server wrapper also defaults the Phoenix log level to `info` so
you see room and dispatch progress instead of full dev query spam.

If this is your first run on a new machine, do `bin/setup` once before starting
the three-terminal flow above.

If you want the older operator-only wrapper, `bin/demo-first-slice` now delegates
to `setup/hive live-demo`.

For live AI runs, `bin/live-demo-server` and `bin/demo-first-slice` honor:

- `ROOM_ID`
- `JIDO_HIVE_TURN_TIMEOUT_MS`
- `JIDO_HIVE_WAIT_TIMEOUT_MS`

If you already have live connector connections, `bin/live-demo-server` can also
publish automatically when these env vars are set before launch:

- `JIDO_HIVE_GITHUB_CONNECTION`
- `JIDO_HIVE_GITHUB_REPO`
- `JIDO_HIVE_NOTION_CONNECTION`
- `JIDO_HIVE_NOTION_DATA_SOURCE_ID`
- `JIDO_HIVE_NOTION_TITLE_PROPERTY`
- `JIDO_HIVE_AUTO_PUBLISH=1`

## Setup Toolkit

Use [setup/README.md](setup/README.md) for the guided local operator flow.

The main entrypoint is:

```bash
setup/hive help
```

That wrapper turns the raw install / connection / publish API flow into a small
set of shell commands with defaults, waiting helpers, input validation, and JSON
output.

For the fastest local run, prefer the three-command path above with
`bin/live-demo-server`.

## Manual Flow

Wait for the local server and both targets:

```bash
setup/hive wait-server
setup/hive wait-targets
```

Create a room:

```bash
setup/hive create-room room-manual-1
```

Run the room:

```bash
setup/hive run-room room-manual-1 --turn-timeout-ms 180000
```

Fetch the publication plan:

```bash
setup/hive publication-plan room-manual-1
```

## Deploy

Deployments now go through `coolify_ex` from inside `jido_hive_server`, with a
repo-root manifest at [.coolify_ex.exs](/home/home/p/g/n/jido_hive/.coolify_ex.exs).

From this repo root:

```bash
export COOLIFY_BASE_URL="https://coolify.example.com"
export COOLIFY_TOKEN="..."
export COOLIFY_APP_UUID="..."
scripts/deploy_coolify.sh
```

The wrapper installs the dev-only deployment dependency if needed, then runs:

```bash
cd jido_hive_server
MIX_ENV=dev mix coolify.deploy
```

The Mix task is the real deployment implementation. The shell script only gives
you a convenient repo-root entrypoint for this monorepo.

Useful variants:

```bash
scripts/deploy_coolify.sh --no-push
scripts/deploy_coolify.sh --project server
scripts/deploy_coolify.sh --force --instant
scripts/deploy_coolify.sh --skip-verify
```

`coolify_ex` now discovers `.coolify_ex.exs` by walking up parent directories,
so the nested `jido_hive_server` Mix project can use the repo-root manifest
without an explicit `--config` path.

## Live GitHub / Notion Path

The setup toolkit wraps the live connector flow. The full guide is in
[setup/README.md](setup/README.md).

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

Execute publication runs:

```bash
setup/hive publish room-manual-1 \
  --github-connection connection-github-1 \
  --github-repo owner/repo \
  --notion-connection connection-notion-1 \
  --notion-data-source-id data-source-id \
  --notion-title-property Name
```

Then inspect the durable publication history:

```bash
setup/hive publication-runs room-manual-1
```

## Client Env

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

## Notes

- Live provider turns can finish as `publication_ready` or `in_review`
  depending on whether the model actually emits a `PUBLISH` action.
- The client now performs one strict no-tool repair pass when a provider
  returns prose or malformed JSON instead of the room contract.
- The default Codex runtime profile is now `gpt-5.4` with `low` reasoning
  unless you override `JIDO_HIVE_MODEL` or `JIDO_HIVE_REASONING_EFFORT`.
