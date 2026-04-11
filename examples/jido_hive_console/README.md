# Jido Hive Console

`examples/jido_hive_console` is the runnable composition layer for the Jido Hive
operator console.

It now composes:

- `jido_hive_client`
- `jido_hive_switchyard_site`
- `jido_hive_switchyard_tui`
- generic Switchyard packages pulled in through those package dependencies

## Current Contract

- `jido_hive_server` owns room truth
- `jido_hive_client` owns reusable operator and room-session behavior
- `jido_hive_switchyard_site` owns the Jido Hive site mapping over Switchyard
  contracts
- `jido_hive_switchyard_tui` owns the Jido-specific terminal workflow
- Switchyard remains generic platform/runtime code beneath those packages
- this example package owns only composition, CLI defaults, and smoke scripts
- this example package does not depend directly on `ex_ratatui`

If a room behavior cannot be reproduced from `jido_hive_client`, the seam is
still wrong.

## Quick Start

### Build the example escript

```bash
cd examples/jido_hive_console
mix deps.get
mix escript.build
```

### Launch the TUI

Local:

```bash
./hive console --local --participant-id alice --debug
```

Production:

```bash
./hive console --prod --participant-id alice --debug
```

Built-in help:

```bash
./hive help
./hive console --help
./hive workflow room-smoke --help
```

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

## Recommended Local Startup

From the repo root, the normal developer flow is:

```bash
bin/live-demo-server
bin/hive-clients
```

Then, from this package:

```bash
cd examples/jido_hive_console
mix escript.build
./hive console --local --participant-id alice --debug
```

This keeps the example package thin: it composes the Switchyard-backed Jido Hive
TUI without taking on room truth or reusable client behavior.

## Debugging Order

Always debug in this order:

1. server truth
2. headless `jido_hive_client`
3. Jido Hive Switchyard TUI
4. this example composition layer only if the handoff itself is broken

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

## Examples

- [test/jido_hive_console/cli_test.exs](test/jido_hive_console/cli_test.exs) covers console option parsing and direct-room startup behavior.
- [test/jido_hive_console/console_test.exs](test/jido_hive_console/console_test.exs) verifies that the example delegates startup into the Switchyard-backed TUI package.
- [test/jido_hive_console/workflow_script_test.exs](test/jido_hive_console/workflow_script_test.exs) covers the scripted `workflow room-smoke` path over the headless client seam.

## What Lives Here Now

- [lib/jido_hive_console.ex](lib/jido_hive_console.ex): example entrypoint
- [lib/jido_hive_console/cli.ex](lib/jido_hive_console/cli.ex): console CLI and
  workflow smoke entry
- [lib/jido_hive_console/workflow_script.ex](lib/jido_hive_console/workflow_script.ex):
  scripted smoke path over `JidoHiveClient.HeadlessCLI`

## Developer Workflow

Run package-local checks from this directory:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
mix docs --warnings-as-errors
```

For repo-wide validation:

```bash
cd ../..
mix ci
```

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
