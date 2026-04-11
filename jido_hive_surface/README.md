# Jido Hive Surface

`jido_hive_surface` is the UI-neutral operator surface for `jido_hive`.

It sits above `jido_hive_client` and below presentation packages such as:

- `jido_hive_switchyard_site`
- `jido_hive_switchyard_tui`
- `jido_hive_web`

This package owns reusable service composition for room and publication
workflows. It does not own:

- authoritative server truth
- terminal rendering
- Phoenix rendering
- worker runtime behavior

## Quick Start

```bash
cd jido_hive_surface
mix deps.get
iex -S mix
```

List rooms through the shared surface:

```elixir
JidoHiveSurface.list_rooms("http://127.0.0.1:4000/api")
```

Load a room workspace:

```elixir
JidoHiveSurface.load_room_workspace("http://127.0.0.1:4000/api", "room-1")
```

Normalize a create-room form payload:

```elixir
JidoHiveSurface.normalize_create_attrs(%{"brief" => "Investigate auth path"})
```

## Responsibilities

- list rooms
- load room workspaces
- load provenance
- create rooms
- start and inspect room runs
- submit steering messages
- load publication workspaces
- publish room outputs

## Package Boundary

Use this package when you need:

- a UI-neutral application seam for room and publication workflows
- the same workflow interface from TUI and web packages
- reusable room create/run/publish orchestration that should not live inside
  Phoenix or terminal code

Do not use this package for:

- room truth
- raw HTTP transport concerns
- worker runtime execution
- rendering logic

Those belong in `jido_hive_server`, `jido_hive_client`,
`jido_hive_worker_runtime`, and the UI packages respectively.

## User-Facing Flows

The shared surface currently supports:

- room list and room workspace loading
- provenance inspection
- room create
- room run
- steering-message submit
- publication workspace loading
- publication submit

## Developer Workflow

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
- [Architecture](../docs/architecture.md)
- [Jido Hive Client README](../jido_hive_client/README.md)
- [Jido Hive Web README](../jido_hive_web/README.md)
- [Jido Hive Switchyard TUI README](../jido_hive_switchyard_tui/README.md)
