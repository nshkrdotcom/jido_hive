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
