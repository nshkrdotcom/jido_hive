# JidoHiveClient

`jido_hive_client` is the local executor for `jido_hive`.

It connects outbound to the Phoenix relay, advertises a session target, and
runs collaboration turns through `Jido.Harness` on the ASM runtime-driver path.

When started through the repo-level wrappers, it also prints human-readable
status lines for relay join, target readiness, turn execution, repair retries,
and result publication.

## What It Does

- joins a relay topic over websockets
- advertises one `codex.exec.session` target
- receives `job.start` packets with a collaboration envelope
- builds a strict JSON run contract from that envelope
- executes the turn through `Jido.Harness -> asm -> ASM`
- carries optional nested `execution_surface` / `execution_environment`
  contracts from the relay/session envelope into the ASM runtime-driver path
- performs one strict no-tool repair pass if the provider returns prose instead
  of the JSON room contract
- returns structured actions, tool events, approvals, artifacts, and execution
  metadata as `job.result`

## CLI

The app is usually started through the repo-level `bin/client` wrapper, but the
raw CLI accepts:

```bash
mix run --no-halt -e 'JidoHiveClient.CLI.main(System.argv())' -- \
  --url ws://127.0.0.1:4000/socket/websocket \
  --relay-topic relay:workspace-local \
  --workspace-id workspace-local \
  --user-id user-architect \
  --participant-id architect \
  --participant-role architect \
  --target-id target-architect \
  --capability-id codex.exec.session \
  --workspace-root /path/to/repo \
  --provider codex \
  --model gpt-5.4 \
  --reasoning-effort low
```

Optional execution flags:

- `--model`
- `--reasoning-effort`
- `--timeout-ms`
- `--cli-path`

The repo-level `bin/client` wrapper defaults to `gpt-5.4` with `low`
reasoning for the Codex path unless you override those values explicitly.

The future-facing room/session envelope is now:

- `session.provider`
- `session.execution_surface`
- `session.execution_environment`
- `session.provider_options`

Existing `workspace_root` and provider shorthands still project into that shape
for the default local execution path.

## Dev

```bash
mix deps.get
mix test
mix quality
```
