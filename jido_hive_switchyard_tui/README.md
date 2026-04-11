# Jido Hive Switchyard TUI

`jido_hive_switchyard_tui` hosts the Jido Hive operator workflow on top of the
generic Switchyard TUI shell.

It owns Jido-specific screen logic, not generic terminal platform behavior.

## Responsibilities

- mount the Jido Hive operator workflow into the generic Switchyard TUI host
- own Jido-specific room, provenance, and publication interaction state
- render the Jido Hive workflow without re-owning room truth
- keep generic shell, daemon, and host concerns in Switchyard

## Dependencies

- `jido_hive_switchyard_site`
- `jido_hive_client`
- generic Switchyard TUI and local-site packages

`ex_ratatui` is owned by the Switchyard host dependency chain, not by the
example console package.

## Quick Start

The preferred manual launch path is still the example composition package, but
this package can also be exercised directly from `iex`.

Normal local stack:

```bash
cd ..
bin/live-demo-server
bin/client-worker --worker-index 1
bin/client-worker --worker-index 2
```

Then, from this package:

```bash
cd jido_hive_switchyard_tui
mix deps.get
iex -S mix
```

Launch the mounted Jido Hive workflow directly:

```elixir
JidoHive.Switchyard.TUI.run(
  api_base_url: "http://127.0.0.1:4000/api",
  participant_id: "alice",
  participant_role: "coordinator",
  authority_level: "binding"
)
```

## Current Internal Split

- the public entry module for mounting the Jido Hive workflow into Switchyard
- a private state module for screen-local room and publication state
- a private mount/update module for event mapping and app callbacks
- a private runtime module for async room and publication commands
- a private view module for room, graph, and overlay rendering

## Debugging Order

1. server truth
2. `jido_hive_client`
3. this package
4. the example composition layer

## Examples

- [test/jido_hive/switchyard/tui/rooms_mount_test.exs](test/jido_hive/switchyard/tui/rooms_mount_test.exs) covers room loading, room-open behavior, and room-specific key handling.
- [test/jido_hive/switchyard/tui/state_test.exs](test/jido_hive/switchyard/tui/state_test.exs) covers cursor bounds and selected-context state transitions.

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
cd ..
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

## Related Reading

- [Workspace README](../README.md)
- [Jido Hive Client README](../jido_hive_client/README.md)
- [Jido Hive Switchyard Site README](../jido_hive_switchyard_site/README.md)
- [Jido Hive Console README](../examples/jido_hive_console/README.md)
- [Debugging Guide](../docs/debugging_guide.md)
