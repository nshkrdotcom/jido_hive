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

- `jido_hive_client`
- generic Switchyard contracts only

This package must not depend on `ex_ratatui`.

## Quick Start

This package becomes useful once the local Jido Hive server is running. A normal
local stack is:

```bash
cd ..
bin/live-demo-server
```

Then, from this package:

```bash
cd jido_hive_switchyard_site
mix deps.get
iex -S mix
```

The primary headless seam is `JidoHive.Switchyard.Site.Client`:

```elixir
JidoHive.Switchyard.Site.Client.list_rooms("http://127.0.0.1:4000/api")
```

## Current Modules

- `JidoHive.Switchyard.Site`
- `JidoHive.Switchyard.Site.Client`

## Examples

- [test/jido_hive/switchyard/site_test.exs](test/jido_hive/switchyard/site_test.exs) covers site/app descriptors, resource mapping, and workflow detail rendering.
- [test/jido_hive/switchyard/site/client_test.exs](test/jido_hive/switchyard/site/client_test.exs) covers room catalog, structured room workspace loading, publication workspace loading, steering submission, and publish payload construction.

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
- [Jido Hive Client README](../jido_hive_client/README.md)
- [Jido Hive Console README](../examples/jido_hive_console/README.md)
- [Debugging Guide](../docs/debugging_guide.md)
