# Jido Hive TermUI Console

`jido_hive_termui_console` is the first formal product-style consumer of the
`jido_hive_client` embedded runtime.

It exists to prove the human-first participation path end to end:

- a human types normal chat text
- the local embedded client intercepts that text into a structured contribution
- the contribution is submitted to the authoritative room server
- the UI refreshes against room timeline and context surfaces
- the human can inspect context and accept a selected object into a decision flow

This project matters because it shows that `jido_hive` does not require a
browser or a daemon-only UX to support human participation.

## Table of contents

- [What this example proves](#what-this-example-proves)
- [Current UI shape](#current-ui-shape)
- [How it is built](#how-it-is-built)
- [Prerequisites](#prerequisites)
- [Run locally](#run-locally)
- [Interaction model](#interaction-model)
- [CLI options](#cli-options)
- [Development notes](#development-notes)
- [Troubleshooting](#troubleshooting)
- [Related docs](#related-docs)

## What this example proves

This package is a narrow but important proof:

- the embedded client runtime is sufficient for a real local consumer
- human chat can enter the room as structured context without inventing a second
  server-side API just for the UI
- timeline and context inspection surfaces are already rich enough to support a
  useful operator-style console
- selected-context prompt authoring can create deliberate graph structure from
  normal terminal input
- server-side derived signals such as contradiction events and stale-context
  annotations can be rendered by a client without pushing graph logic into the UI

This example is intentionally not a full product shell. It is the thinnest UI
that exercises the real participation path.

## Current UI shape

The console is built around three visible regions:

- left pane: conversation and room timeline projection
- right pane: structured context object list
- bottom pane: input buffer for normal chat text

The footer shows current status and the key bindings.

The important part is not the layout itself. The important part is that the UI
is driven by the embedded client snapshot rather than by ad hoc HTTP calls spread
throughout the view layer.

The context pane is no longer just a flat list. Each row now carries lightweight
graph cues:

- incoming and outgoing edge counts
- stale markers
- contradiction markers

## How it is built

The example uses:

- `term_ui` for terminal rendering and event handling
- `jido_hive_client` for the embedded participant runtime
- the server room APIs indirectly through the client runtime

Important local files:

- `lib/jido_hive_termui_console/cli.ex`
  Command-line parsing and startup.
- `lib/jido_hive_termui_console/app.ex`
  Main `term_ui` application loop, update logic, and rendering.
- `lib/jido_hive_termui_console/model.ex`
  Local UI model.
- `lib/jido_hive_termui_console/projection.ex`
  Snapshot-to-screen-line projection helpers.

The example depends on the local `term_ui` tree when present at:

- `/home/home/p/g/n/term_ui`

Related local references:

- `/home/home/p/g/n/term_ui/guides/user`
- `/home/home/p/g/n/term_ui/examples`

If the local tree is not present, the example falls back to the Hex dependency
declared in `mix.exs`.

## Prerequisites

Before running the console, you need:

- repo setup completed with `bin/setup`
- a running `jido_hive_server`
- an existing room id

The server will usually be started with one of:

```bash
bin/server
```

or:

```bash
bin/live-demo-server
```

Local API default:

- `http://127.0.0.1:4000/api`

## Run locally

From the example directory:

```bash
cd /home/home/p/g/n/jido_hive/examples/jido_hive_termui_console
mix deps.get
mix run -- --room-id room-123 --participant-id alice
```

That starts the embedded runtime, snapshots the current room, and opens the UI.

### Typical local workflow

1. Start the server.
2. Create or identify a room with `bin/hive-control` or `setup/hive`.
3. Launch the console with that room id.
4. Type chat into the input pane.
5. Watch the timeline and context panes update after submission.
6. Move selection in the context pane and accept a selected object when needed.

## Interaction model

The full interaction loop is:

1. The CLI starts the embedded client runtime.
2. The embedded runtime subscribes to its local runtime and polls the server room
   APIs.
3. The app renders a snapshot containing:
   - participant info
   - room timeline entries
   - current context objects
   - runtime status
4. When the user presses `Enter`, the current text buffer is sent to
   `submit_chat/2`.
5. The client interceptor and backend turn that chat into a structured
   contribution.
6. The contribution is posted to the server.
7. The embedded runtime refreshes its snapshot.
8. The console redraws with the updated timeline and context.

Accepting a selected object follows the same shape, except it uses
`accept_context/3` to create a decision-style contribution rooted in the selected
context object. The resulting decision currently `derives_from` the selected
node so it participates in the server-side graph immediately.

## Relation authoring modes

The console now supports explicit graph-authoring modes.

### Why this exists

Without mode selection, human chat with a selected context object is too
ambiguous. The UI now lets the human decide whether the next contribution should
act like:

- contextual authoring
- an explicit reference
- a derivation
- supporting evidence
- a contradiction
- plain chat with no anchoring

### Current modes

- `contextual`
  Default mode. The embedded client chooses a relation based on the generated
  object type.
- `references`
  New semantic objects reference the selected node.
- `derives_from`
  New semantic objects derive from the selected node.
- `supports`
  New semantic objects support the selected node.
- `contradicts`
  New semantic objects contradict the selected node.
- `none`
  Submit plain chat. No selected-context anchoring is applied.

### Contextual defaults

Current contextual defaults are:

- `hypothesis` -> `derives_from`
- `evidence` -> `supports`
- `contradiction` -> `contradicts`
- `decision_candidate` -> `derives_from`
- `question` -> `references`
- `note` -> `references`

If a selected context exists and the deterministic backend would otherwise only
emit a plain `message`, the client adds one anchored `note` so the action can
still shape the graph.

## CLI options

Current options:

- `--api-base-url`
  Default: `http://127.0.0.1:4000/api`
- `--room-id`
  Required
- `--participant-id`
  Default: `human-local`
- `--participant-role`
  Default: `collaborator`
- `--poll-interval-ms`
  Default: `500`

## Keys

- `Enter`
  Submit the current input buffer as chat.
- `Up` / `Down`
  Move the selected context object.
- `Ctrl+A`
  Accept the selected context object into a binding decision-style contribution.
- `Ctrl+T`
  Switch to `contextual` mode.
- `Ctrl+F`
  Switch to explicit `references` mode.
- `Ctrl+D`
  Switch to explicit `derives_from` mode.
- `Ctrl+S`
  Switch to explicit `supports` mode.
- `Ctrl+X`
  Switch to explicit `contradicts` mode.
- `Ctrl+N`
  Switch to `none` mode for plain chat.
- `Ctrl+R`
  Refresh immediately.
- `Ctrl+Q`
  Quit.

## Development notes

This project is deliberately small, so changes should stay disciplined:

- keep server semantics out of the UI layer
- use the embedded client boundary instead of raw ad hoc room API calls
- keep rendering and snapshot projection separate
- prefer testing projection and model behavior directly when possible
- keep graph authoring explicit enough that a human can predict what relations
  will be created

### Setup

```bash
cd /home/home/p/g/n/jido_hive/examples/jido_hive_termui_console
mix setup
```

### Focused quality gate

```bash
mix quality
```

### Repo-wide quality gate

```bash
cd /home/home/p/g/n/jido_hive
mix ci
```

## Troubleshooting

### `--room-id is required`

Pass a room id explicitly:

```bash
mix run -- --room-id room-123 --participant-id alice
```

### The UI opens but shows stale data

Use `Ctrl+R` to force a refresh and confirm the server is reachable at the
configured `--api-base-url`.

### The example cannot start because `term_ui` is missing

Make sure either:

- the local tree exists at `/home/home/p/g/n/term_ui`, or
- the Hex dependency can be resolved during `mix deps.get`

### Chat submits but context does not look rich

The current backend is deterministic and intentionally narrow. It is good enough
to create useful graph structure when you select a context node and choose a
relation mode, but it is not trying to feel like a full language-model copilot.

## Related docs

- [Root README](../../README.md)
- [Server README](../../jido_hive_server/README.md)
- [Client README](../../jido_hive_client/README.md)
