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

## Current Modules

- `JidoHive.Switchyard.Site`
- `JidoHive.Switchyard.Site.Client`

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
