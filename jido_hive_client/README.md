# JidoHiveClient

`jido_hive_client` is the local executor for `jido_hive`.

It connects outbound to the Phoenix relay, advertises a session target, and
runs collaboration turns through `Jido.Harness` on the ASM runtime-driver path.

## What It Does

- joins a relay topic over websockets
- advertises one `codex.exec.session` target
- receives `job.start` packets with a collaboration envelope
- builds a strict JSON run contract from that envelope
- executes the turn through `Jido.Harness -> asm -> ASM`
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
  --provider codex
```

Optional execution flags:

- `--model`
- `--timeout-ms`
- `--cli-path`

## Dev

```bash
mix deps.get
mix test
mix quality
```
