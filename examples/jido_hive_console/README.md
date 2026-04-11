# Jido Hive Console Compatibility Wrapper

`examples/jido_hive_console` is no longer the primary terminal UI
implementation for `jido_hive`.

The live terminal UX now belongs in the separate `switchyard` repo.
This package remains for two reasons:

- compatibility: `./hive console ...` still launches the Switchyard TUI
- scripting: `workflow room-smoke` still provides a small non-TUI smoke path

## Current Contract

- `jido_hive_server` owns room truth
- `jido_hive_client` owns reusable operator and room-session behavior
- Switchyard owns the terminal UI implementation and the `ex_ratatui`
  dependency
- this package is a bridge, not a second UI stack

If a room behavior cannot be reproduced from `jido_hive_client`, the seam is
still wrong.

## Quick Start

### Build the compatibility escript

```bash
cd examples/jido_hive_console
mix deps.get
mix escript.build
```

### Launch the TUI through Switchyard

Local:

```bash
./hive console --local --participant-id alice --debug
```

Production:

```bash
./hive console --prod --participant-id alice --debug
```

The wrapper will try, in order:

1. `SWITCHYARD_BIN`
2. `switchyard` on `PATH`
3. a built sibling Switchyard escript
4. `mix run` inside the sibling Switchyard TUI app

If none of those are available, the wrapper exits with
`{:error, :switchyard_not_found}`.

### Run the headless room smoke path

```bash
./hive workflow room-smoke \
  --local \
  --brief "local smoke room" \
  --text "hello from the scripted path" \
  --text "second message"
```

The same helper is available from the repo root:

```bash
bin/hive-room-smoke \
  --brief "local smoke room" \
  --text "hello from the scripted path"
```

## Debugging Order

Always debug in this order:

1. server truth
2. headless `jido_hive_client`
3. Switchyard TUI
4. this compatibility wrapper only if the launch handoff itself is broken

Representative headless checks:

```bash
cd ../../jido_hive_client
mix escript.build

./jido_hive_client room show --api-base-url https://jido-hive-server-test.app.nsai.online/api --room-id <room-id>
./jido_hive_client room workflow --api-base-url https://jido-hive-server-test.app.nsai.online/api --room-id <room-id>
./jido_hive_client room workspace --api-base-url https://jido-hive-server-test.app.nsai.online/api --room-id <room-id>
./jido_hive_client room provenance --api-base-url https://jido-hive-server-test.app.nsai.online/api --room-id <room-id> --context-id <context-id>
./jido_hive_client room publish-plan --api-base-url https://jido-hive-server-test.app.nsai.online/api --room-id <room-id>
```

## What Lives Here Now

- [lib/jido_hive_console.ex](lib/jido_hive_console.ex): compatibility entrypoint
- [lib/jido_hive_console/cli.ex](lib/jido_hive_console/cli.ex): wrapper CLI and
  workflow smoke entry
- [lib/jido_hive_console/switchyard_bridge.ex](lib/jido_hive_console/switchyard_bridge.ex):
  Switchyard handoff logic
- [lib/jido_hive_console/workflow_script.ex](lib/jido_hive_console/workflow_script.ex):
  scripted smoke path over `JidoHiveClient.HeadlessCLI`

## Quality

From this directory:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
mix docs --warnings-as-errors
```

For repo-wide checks, use the root workspace:

```bash
cd ../..
mix ci
```
