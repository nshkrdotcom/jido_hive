# Jido Hive Switchyard Site

`jido_hive_switchyard_site` maps Jido Hive workflow truth into Switchyard's
generic site contracts.

This package is headless. It owns no terminal rendering.

## Responsibilities

- declare the Jido Hive site and app descriptors
- expose room and publication resources to generic Switchyard hosts
- map resource detail and recommended actions from `jido_hive_client`
- keep all Jido Hive workflow semantics outside the Switchyard repo

## Dependencies

- `jido_hive_surface`
- generic Switchyard contracts only

This package must not depend on `jido_hive_worker_runtime`.

This package must not depend on `ex_ratatui`.

This package must not own generalized operator service helpers.
Those now live in [../jido_hive_surface/README.md](../jido_hive_surface/README.md).

## Quick Start

This package becomes useful once the local Jido Hive server is running. The
Switchyard-backed TUI composes this package indirectly; you normally do not call
it by itself.

For package-local verification:

```bash
cd jido_hive_switchyard_site
mix deps.get
mix test
```

## Current Modules

- `JidoHive.Switchyard.Site`

## User-Facing Role

This package contributes:

- Jido Hive site metadata
- room and publication resource mapping
- generic action/resource/detail data for Switchyard hosts

It does not own room loading, provenance loading, publication loading, or room
mutation workflows directly anymore.

## Examples

- [test/jido_hive/switchyard/site_test.exs](test/jido_hive/switchyard/site_test.exs) covers site/app descriptors, resource mapping, and workflow detail rendering.

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

For repo-wide checks, use the workspace root:

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
- [Jido Hive Surface README](../jido_hive_surface/README.md)
- [Jido Hive Console README](../examples/jido_hive_console/README.md)
- [Debugging Guide](../docs/debugging_guide.md)
