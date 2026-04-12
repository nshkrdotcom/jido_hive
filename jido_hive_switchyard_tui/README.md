# Jido Hive Switchyard TUI

`jido_hive_switchyard_tui` hosts the Jido Hive operator workflow on top of the
generic Switchyard Workbench runtime.

It owns Jido-specific room workflow state and views, not generic terminal
platform behavior.

## Responsibilities

- expose Jido Hive app components for the Switchyard TUI
- own room, provenance, and explicit publication-extension interaction state
- render the Jido Hive workflow with Workbench widgets
- keep generic shell, runtime, and renderer concerns in Switchyard core

## Dependencies

- `jido_hive_surface`
- `jido_hive_switchyard_site`
- `switchyard_tui`
- `workbench_tui_framework`
- `workbench_widgets`

This package must not depend on `jido_hive_worker_runtime`.

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

Launch the Jido Hive workflow directly:

```elixir
JidoHive.Switchyard.TUI.run(
  api_base_url: "http://127.0.0.1:4000/api",
  participant_id: "alice",
  participant_role: "coordinator"
)
```

## Current Internal Split

- the public entry module for launching the Jido Hive workflow through Switchyard
- a private component module for room interaction behavior
- a private state module for room and publication-extension workflow state
- a private runtime module for async commands over `jido_hive_surface`
- a private view module for room, graph, and overlay rendering

## Debugging Order

1. server truth
2. `jido_hive_client`
3. this package
4. the example composition layer

## Examples

- [test/jido_hive/switchyard/tui/rooms_mount_test.exs](test/jido_hive/switchyard/tui/rooms_mount_test.exs) covers room loading, room-open behavior, and room-specific key handling through the component seam.
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

## Related Reading

- [Workspace README](../README.md)
- [Jido Hive Surface README](../jido_hive_surface/README.md)
- [Jido Hive Client README](../jido_hive_client/README.md)
- [Jido Hive Switchyard Site README](../jido_hive_switchyard_site/README.md)
- [Jido Hive Console README](../examples/jido_hive_console/README.md)
- [Debugging Guide](../docs/debugging_guide.md)
