# Jido Hive Web

`jido_hive_web` is the Phoenix LiveView browser UI for `jido_hive`.

It is a separate mix project on purpose. It consumes the same reusable operator
surface as the Switchyard TUI instead of reaching into server internals or
redefining room semantics in Phoenix.

## Responsibilities

- browser routing and LiveView state
- room list and room create flow
- room detail, provenance, steering, and run controls
- publication-plan review and publish flow

It does not own:

- room truth
- worker runtime execution
- terminal presentation
- low-level operator transport

## Dependencies

- `jido_hive_surface`
- `jido_hive_client` for `RoomSession`
- Phoenix / LiveView / Bandit

This package must not depend on Switchyard or `ex_ratatui`.

## Quick Start

Start the local server first:

```bash
cd ..
bin/live-demo-server
```

Then, from this package:

```bash
cd jido_hive_web
mix setup
mix phx.server
```

Open:

- `http://127.0.0.1:4100/rooms`

The web app talks to `http://127.0.0.1:4000/api` by default.

Override that with:

```bash
JIDO_HIVE_WEB_API_BASE_URL=http://127.0.0.1:4000/api mix phx.server
```

Optional operator identity overrides:

```bash
JIDO_HIVE_WEB_SUBJECT=alice
JIDO_HIVE_WEB_PARTICIPANT_ID=alice
JIDO_HIVE_WEB_PARTICIPANT_ROLE=coordinator
JIDO_HIVE_WEB_AUTHORITY_LEVEL=binding
```

## User Flows

- `/rooms`
  saved room list and room create flow
- `/rooms/:room_id`
  room workspace with steering, provenance, and run controls
- `/rooms/:room_id/publish`
  publication workspace and publish form

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

## Debugging Order

Always debug in this order:

1. server truth
2. headless `jido_hive_client`
3. shared `jido_hive_surface`
4. this Phoenix UI

If a room issue reproduces headlessly, it is not a web-only bug.

## Examples

- [test/jido_hive_web_web/live/room_index_live_test.exs](test/jido_hive_web_web/live/room_index_live_test.exs)
  covers the room list and room-create flow
- [test/jido_hive_web_web/live/room_show_live_test.exs](test/jido_hive_web_web/live/room_show_live_test.exs)
  covers room detail, provenance, steering, and run controls
- [test/jido_hive_web_web/live/publication_show_live_test.exs](test/jido_hive_web_web/live/publication_show_live_test.exs)
  covers the publication workspace and publish flow

## Related Reading

- [Workspace README](../README.md)
- [Architecture](../docs/architecture.md)
- [Jido Hive Surface README](../jido_hive_surface/README.md)
- [Jido Hive Client README](../jido_hive_client/README.md)
