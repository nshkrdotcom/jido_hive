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

The console is now a five-screen operator shell:

- lobby: local room launcher backed by `~/.config/hive/rooms.json`
- room: conversation, context, event poller, input, and graph-authoring controls
- conflict: contradiction side-by-side review plus manual or AI-assisted resolution
- publish: server-driven publication plan with dynamic required bindings
- wizard: new-room creation from live `/targets` and `/policies` data

The room screen still uses a pane layout:

- conversation pane: recent timeline projection
- context pane: structured context objects or provenance drill-down
- events pane: short-polled room activity feed
- input pane: current chat buffer

The important part is not the layout itself. The important part is that the UI
is driven by the embedded client snapshot and thin HTTP boundary helpers rather
than by ad hoc room logic spread throughout the view layer.

The context pane surfaces lightweight graph cues per row:

- incoming and outgoing edge counts
- stale markers
- contradiction markers
- `[BINDING]` authority markers

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
- `lib/jido_hive_termui_console/nav.ex`
  Screen transitions and room-process lifecycle.
- `lib/jido_hive_termui_console/projection.ex`
  Snapshot-to-screen-line projection helpers.
- `lib/jido_hive_termui_console/config.ex`
  Local config, room registry, and config-file bootstrap.
- `lib/jido_hive_termui_console/auth.ex`
  Cached connector auth state for publish flows.
- `lib/jido_hive_termui_console/http.ex`
  Thin `:httpc` wrapper for lobby, publish, and wizard fetches.
- `lib/jido_hive_termui_console/screens/`
  Screen-specific key maps and rendering for lobby, room, conflict, publish, and wizard.

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
- optionally one or more workers if you want live room execution

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
mix setup
mix escript.build
```

Open the lobby:

```bash
./hive console
```

Open a room directly:

```bash
./hive console --room-id room-123
```

Bootstrap cached connector auth for publish flows:

```bash
./hive auth login github
./hive auth login notion
```

### Typical local workflow

1. Start the server.
2. Start workers with `bin/client-worker`, `bin/hive-clients`, or the live-demo helpers.
3. Launch `./hive console`.
4. Open an existing room from the lobby or create one with the wizard.
5. Type chat into the room screen and watch timeline, context, and event panes refresh.
6. Use provenance drill-down, conflict resolution, and publish when the room reaches those states.

## Interaction model

The full interaction loop is:

1. `hive console` loads local config from `~/.config/hive/`.
2. The lobby screen reads `rooms.json` and fetches each room snapshot over HTTP.
3. Opening a room starts the embedded runtime plus a separate short-poll event log task.
4. The room screen renders participant identity, room snapshot, event feed, and current input.
5. Pressing `Enter` sends the buffer through `Embedded.submit_chat/2`.
6. The embedded client interceptor and backend turn chat into a structured contribution.
7. The contribution is posted to the authoritative room server.
8. The embedded runtime refreshes, the event poller advances, and the console redraws.

Accepting a selected object follows the same shape, except it uses
`accept_context/3` to create a binding decision rooted in the selected context
object. Conflict resolution is separate: the conflict screen submits one direct
HTTP contribution with two `resolves` relations so it matches server graph
semantics.

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
- `resolves`
  New semantic objects resolve the selected node.
- `none`
  Submit plain chat. No selected-context anchoring is applied.

### Contextual defaults

Current contextual defaults are:

- `hypothesis` -> `derives_from`
- `evidence` -> `supports`
- `contradiction` -> `contradicts`
- `decision` -> `resolves`
- `decision_candidate` -> `resolves`
- `question` -> `references`
- `note` -> `references`

If a selected context exists and the deterministic backend would otherwise only
emit a plain `message`, the client adds one anchored `note` so the action can
still shape the graph.

## CLI options

### Commands

- `./hive console`
  Open the lobby using `~/.config/hive/config.json`.
- `./hive console --room-id <id>`
  Skip the lobby and open a room directly.
- `./hive auth login github`
  Start the v1 device-flow scaffold for GitHub.
- `./hive auth login notion`
  Start the v1 device-flow scaffold for Notion.
- `./hive room create`
  Intentionally not implemented; use the interactive wizard from the lobby.

### Console options

- `--api-base-url`
  Default: `http://127.0.0.1:4000/api`
- `--room-id`
  Optional direct-open target
- `--participant-id`
  Default: generated human identity or config file value
- `--participant-role`
  Default: `coordinator`
- `--authority-level`
  Default: `binding`
- `--poll-interval-ms`
  Default: `500`

## Keyboard shortcuts

### Lobby

- `Up` / `Down`: move cursor
- `Enter`: open selected room
- `n`: open the room-creation wizard
- `r`: refetch local room rows
- `d`: remove the selected room id from `rooms.json`
- `q` or `Ctrl+Q`: quit

### Room

- `Up` / `Down`: move selected context object
- `Enter`: submit chat, or open conflict resolution when the selected object is a contradiction
- `Tab`: cycle pane focus
- `Esc`: clear drill mode, clear input, or go back to the lobby
- `Ctrl+A`: accept selected context into a binding decision
- `Ctrl+B`: return to lobby
- `Ctrl+E`: toggle provenance drill-down for the selected object
- `Ctrl+P`: open publish when the room is `publication_ready`
- `Ctrl+R`: refresh the room snapshot
- `Ctrl+T`: `contextual` relation mode
- `Ctrl+F`: `references` relation mode
- `Ctrl+D`: `derives_from` relation mode
- `Ctrl+S`: `supports` relation mode
- `Ctrl+X`: `contradicts` relation mode
- `Ctrl+V`: `resolves` relation mode
- `Ctrl+N`: plain chat mode with no anchoring
- `Ctrl+Q`: quit

### Conflict

- `a`: prefill an accept-left resolution
- `b`: prefill an accept-right resolution
- `s`: dispatch AI synthesis through the chat path
- `Enter`: submit one direct resolution contribution with two `resolves` edges
- `Esc`: return to room
- `Ctrl+Q`: quit

### Publish

- `Space`: toggle the focused channel
- `Tab`: cycle channel and binding inputs
- `Enter`: submit publications
- `r`: refresh cached auth state
- `Esc`: return to room
- `Ctrl+Q`: quit

### Wizard

- `Up` / `Down`: move through policies and worker targets
- `Backspace`: edit the brief on step 0
- `Space`: toggle a worker on step 3
- `Enter`: advance or create the room on the final step
- `Esc`: go back a step or return to the lobby
- `Ctrl+Q`: quit

## Config files

The console creates and reads these files under `~/.config/hive/`:

- `config.json`
  Default API URL, participant id, participant role, authority level, and poll interval.
- `rooms.json`
  Local room registry shown in the lobby. Stale room ids stay removable even when the server returns `404`.
- `credentials.json`
  Cached connector credentials used by the publish screen. File mode is locked to `0600`.

## Auth setup

`hive auth login <provider>` is a v1 device-flow scaffold. It prints:

- a verification URL
- a user code
- the credentials file path

The command does not complete OAuth inside the console yet. It exists so the
publish screen can report a concrete connector path and persist cached auth
state in one location.

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

### The room opens directly but I expected the lobby

The console only skips the lobby when `--room-id <id>` is present. Run:

```bash
./hive console
```

### The UI opens but shows stale data

Use `Ctrl+R` to force a refresh and confirm the server is reachable at the
configured `--api-base-url`.

### The lobby shows a broken room row

The lobby keeps stale room ids visible as removable entries when the server
returns `404`. Press `d` on that row to delete the local id from `rooms.json`.

### Publish says auth is missing

Run one of:

```bash
./hive auth login github
./hive auth login notion
```

Then confirm that `~/.config/hive/credentials.json` contains the cached
credential record expected by the publish screen.

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
