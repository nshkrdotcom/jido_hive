# Jido Hive Console Example

`jido_hive_termui_console` is the first full human-facing console built on top
of the embedded client runtime in `jido_hive_client`.

It proves that `jido_hive` can support real human participation without a
browser and without inventing a second room state model. The server still owns
the room. The console is just a local operator and participant surface.

## Start Here

If you are new, do this first:

1. Run `bin/setup` from the repo root.
2. Build the console once.
3. Pick a mode:
   local default: your own Phoenix server on `http://127.0.0.1:4000/api`
   prod shortcut: the deployed test server on `https://jido-hive-server-test.app.nsai.online/api`
4. Open the console in two terminals with two distinct participant ids.
5. Expect the lobby to be empty on first run until you create a room or open one by id.

From the example directory:

```bash
cd /home/home/p/g/n/jido_hive/examples/jido_hive_termui_console
mix setup
mix escript.build
```

The resulting executable is `./hive`.

## The First-Run Mental Model

The most important thing to understand is this:

- the lobby is not a global room browser
- the lobby is a local room registry backed by `~/.config/hive/rooms.json`
- saved room ids are scoped to the current server API base
- on first run, an empty lobby is normal

What that means in practice:

- if `rooms.json` has no saved room ids yet, the lobby will show no rows
- pressing `Enter` in that state will not work because there is no selected room
- the normal way forward is to press `n` and create a room through the wizard
- if you already know a room id, you can bypass the empty lobby with `--room-id`

So the intended operator loop is:

1. Start the server and workers if you are using local mode.
2. Start the console.
3. Press `n`.
4. Enter a brief.
5. Pick a dispatch policy.
6. Pick one or more worker targets.
7. Confirm to create the room.
8. The room id is saved to `~/.config/hive/rooms.json` for the current server.
9. Future launches will show that room in the lobby.

## Local Onboarding

This is the default path. If you pass no mode flag, the console targets the
local API.

### What you need

- one local server
- at least one connected worker target if you want to create and run a room
- two console terminals if you want to see two human clients in the same system

### Recommended local setup

Terminal 1, start the server:

```bash
bin/live-demo-server
```

Terminal 2, start workers:

```bash
bin/hive-clients
```

That menu can launch one worker, two workers, or more in the same terminal.
Two workers is the best quick demo because the round-robin room flow becomes
easy to see.

Terminal 3, start the first human console:

```bash
cd /home/home/p/g/n/jido_hive/examples/jido_hive_termui_console
./hive console --participant-id alice
```

Terminal 4, start the second human console:

```bash
cd /home/home/p/g/n/jido_hive/examples/jido_hive_termui_console
./hive console --participant-id bob
```

### What you should expect

When the lobby first opens, it may be empty. That does not mean the console is
broken. It usually means `~/.config/hive/rooms.json` has no saved room ids yet.
The local and prod consoles do not share the same saved room list.

If you see an empty lobby:

1. Press `n`.
2. Enter a room brief.
3. Choose a policy.
4. Choose one or more worker targets.
5. Press `Enter` on the confirm step.

That will create the room on the server, save the room id locally, start the
room, and transition you into it. The console opens the room immediately; the
server-side run continues in the background.

### What to do next

In either console:

1. Open the lobby.
2. Press `n` to open the wizard.
3. Select a policy and one or more live worker targets.
4. Create the room.
5. Open that room from both console instances.
6. Submit chat, inspect context, and watch the room update.

If you already have a room id, you can skip the lobby:

```bash
./hive console --room-id room-123 --participant-id alice
```

## Production Onboarding

Use production mode only after at least one prod worker is connected.

The console supports the same server shortcuts used elsewhere in the repo:

- `--local`
  Force `http://127.0.0.1:4000/api`
- `--prod`
  Force `https://jido-hive-server-test.app.nsai.online/api`
- `--api-base-url <url>`
  Override both and point to any compatible server

Precedence is:

1. explicit `--api-base-url`
2. `--prod` or `--local`
3. `~/.config/hive/config.json`
4. built-in local default

### From Scratch

This is the exact production flow.

1. Open a terminal in the repo root:

```bash
cd /home/home/p/g/n/jido_hive
```

2. Start one or more workers against production:

```bash
bin/hive-clients --prod
```

3. In a second terminal, confirm production now has targets:

```bash
cd /home/home/p/g/n/jido_hive
setup/hive --prod targets
```

4. If that command shows no targets, stop here.

Production room creation will not work yet. The console can still open, but
step 3 of the wizard will say `No worker targets available on this server.`

5. If that command shows at least one target, build the console:

```bash
cd /home/home/p/g/n/jido_hive/examples/jido_hive_termui_console
mix escript.build
```

6. Start the first human console:

```bash
./hive console --prod --participant-id alice
```

7. In the console, press `n` to create a room.
   On the confirm step, press `Enter`. The console opens the room immediately
   and the room run continues in the background.

8. If you want a second human participant, open another terminal and run:

```bash
cd /home/home/p/g/n/jido_hive/examples/jido_hive_termui_console
./hive console --prod --participant-id bob
```

### If You Already Know The Room ID

You can skip room creation entirely:

```bash
./hive console --prod --room-id room-123 --participant-id alice
```

## What The Console Does

The console is a five-screen operator shell:

- lobby
  Local room launcher backed by `~/.config/hive/rooms.json`, scoped per server
- room
  Conversation, context, event polling, and graph-authoring controls
- conflict
  Side-by-side contradiction review and manual or AI-assisted resolution
- publish
  Server-driven publication plan with dynamic required bindings
- wizard
  New room creation from live `/targets` and `/policies` data

The room screen uses four panes:

- conversation pane
  Recent timeline projection
- context pane
  Structured context objects or provenance drill-down
- events pane
  Short-polled room activity feed
- input pane
  Current chat buffer

The UI is driven by the embedded client snapshot plus thin HTTP fetches. It
does not own room logic locally.

## Commands

### Main commands

- `./hive console`
  Open the lobby using config from `~/.config/hive/config.json`
- `./hive console --room-id <id>`
  Open one room directly
- `./hive console --prod`
  Use the deployed test server API base
- `./hive console --local`
  Force the local API base
- `./hive console --api-base-url <url>`
  Use any compatible server

### Auth scaffold

- `./hive auth login github`
- `./hive auth login notion`

These commands are v1 device-flow scaffolds. They print a verification URL, a
user code, and the credentials file path. They do not complete OAuth inside the
console, but they give the publish flow a stable local credential surface.

### Intentionally not implemented

- `./hive room create`

Non-interactive room creation is intentionally not wired up in the CLI. Use the
wizard from the lobby.

## Common Options

- `--debug`
  Shortcut for `--log-level debug`
- `--local`
  Force the local API base
- `--prod`
  Force the deployed test API base
- `--api-base-url`
  Override the API base directly
- `--log-level`
  Logger level for the example file logger: `debug`, `info`, `warning`, or `error`
- `--log-file`
  Write logs to a specific file instead of the default path
- `--room-id`
  Open a room immediately instead of starting in the lobby
- `--participant-id`
  Human participant id used by the embedded runtime
- `--participant-role`
  Defaults to `coordinator`
- `--authority-level`
  Defaults to `binding`
- `--poll-interval-ms`
  Defaults to `500`

## Keyboard Shortcuts

### Lobby

- `Up` / `Down`
  Move the cursor
- `Enter`
  Open the selected room
- `n`
  Open the room-creation wizard
- `r`
  Refetch local room rows
- `d`
  Remove the selected room id from `rooms.json`
- `q` or `Ctrl+Q`
  Quit

### Room

- `Up` / `Down`
  Move the selected context object
- `Enter`
  Submit chat, or open conflict resolution when the selected object is a contradiction
- `Tab`
  Cycle pane focus
- `Esc`
  Clear provenance drill, clear input, or go back to the lobby
- `Ctrl+A`
  Accept the selected context object into a binding decision
- `Ctrl+B`
  Return to lobby
- `Ctrl+E`
  Toggle provenance drill-down for the selected object
- `Ctrl+P`
  Open publish when the room status is `publication_ready`
- `Ctrl+R`
  Refresh the room snapshot
- `Ctrl+T`
  `contextual` relation mode
- `Ctrl+F`
  `references` relation mode
- `Ctrl+D`
  `derives_from` relation mode
- `Ctrl+S`
  `supports` relation mode
- `Ctrl+X`
  `contradicts` relation mode
- `Ctrl+V`
  `resolves` relation mode
- `Ctrl+N`
  Plain chat mode with no anchoring
- `Ctrl+Q`
  Quit

### Conflict

- `a`
  Prefill an accept-left resolution
- `b`
  Prefill an accept-right resolution
- `s`
  Dispatch AI synthesis through the chat path
- `Enter`
  Submit one direct resolution contribution with two `resolves` edges
- `Esc`
  Return to room
- `Ctrl+Q`
  Quit

### Publish

- `Space`
  Toggle the focused publication channel
- `Tab`
  Cycle channel and binding inputs
- `Enter`
  Submit publications
- `r`
  Refresh cached auth state
- `Esc`
  Return to room
- `Ctrl+Q`
  Quit

### Wizard

- `Up` / `Down`
  Move through policies and worker targets
- `Backspace`
  Edit the brief on step 0
- `Space`
  Toggle a worker on step 3
- `Enter`
  Advance, or create the room on the final step
- `Esc`
  Go back a step or return to the lobby
- `Ctrl+Q`
  Quit

## Interaction Model

The normal room loop is:

1. The console loads local config from `~/.config/hive/`.
2. The lobby reads the current server's saved room list from `rooms.json` and fetches each room snapshot over HTTP.
3. Opening a room starts the embedded runtime plus a separate short-poll event log task.
4. The room screen renders participant identity, room snapshot, event feed, and input.
5. Pressing `Enter` sends the buffer through `Embedded.submit_chat/2`.
6. The embedded client interceptor and backend turn chat into a structured contribution.
7. The contribution is posted to the authoritative room server.
8. The embedded runtime refreshes, the event poller advances, and the console redraws.

Accepting a selected object uses `accept_context/3` to create a binding
decision. Conflict resolution is separate: the conflict screen submits one
direct HTTP contribution with two `resolves` relations so it matches the
server’s graph semantics.

## Relation Authoring Modes

The console supports explicit graph-authoring modes so human chat can shape the
graph deliberately instead of relying on vague chat interpretation.

### Current modes

- `contextual`
  The embedded client chooses a relation from the generated object type
- `references`
  New semantic objects reference the selected node
- `derives_from`
  New semantic objects derive from the selected node
- `supports`
  New semantic objects support the selected node
- `contradicts`
  New semantic objects contradict the selected node
- `resolves`
  New semantic objects resolve the selected node
- `none`
  Submit plain chat with no selected-context anchoring

### Contextual defaults

- `hypothesis` -> `derives_from`
- `evidence` -> `supports`
- `contradiction` -> `contradicts`
- `decision` -> `resolves`
- `decision_candidate` -> `resolves`
- `question` -> `references`
- `note` -> `references`

If a selected context exists and the deterministic backend would otherwise emit
only a plain `message`, the client adds one anchored `note` so the action can
still shape the graph.

## Config And Local State

The console creates and reads these files under `~/.config/hive/`:

- `config.json`
  Default API URL, participant id, participant role, authority level, and poll interval
- `rooms.json`
  Local room registry shown in the lobby
- `credentials.json`
  Cached connector credentials used by the publish screen
- `termui_console.log`
  File logger output for debugging startup, render, and runtime failures

Stale room ids are intentionally left visible in the lobby as removable rows if
the server returns `404`.

## Publish And Auth

The publish screen fetches the publication plan from the server and renders
channels dynamically from `required_bindings`. Binding field names are not
hardcoded in the TUI.

Auth state is loaded from `credentials.json` and rendered as either:

- cached and ready
- missing, with a concrete `hive auth login <provider>` recovery path

## Prerequisites And Dependencies

Before running the console, you need:

- repo setup completed with `bin/setup`
- a running `jido_hive_server` if you are in local mode
- connected worker targets if you want the wizard to create a runnable room

The example uses:

- `ExRatatui` for terminal rendering, event handling, and text input state
- `jido_hive_client` for the embedded participant runtime
- thin direct HTTP calls for lobby, wizard, conflict, and publish fetches

The shipped `./hive` escript includes an `ExRatatui` bootstrap step that
extracts the packaged NIF from the archive before the console starts.

## Developers

This section is for people changing the console itself.

### Important files

- `lib/jido_hive_termui_console/cli.ex`
  CLI parsing, `--local` and `--prod` mode selection, and command dispatch
- `lib/jido_hive_termui_console.ex`
  Top-level startup and runtime option wiring
- `lib/jido_hive_termui_console/app.ex`
  Main `ExRatatui` app/update loop and message handling
- `lib/jido_hive_termui_console/model.ex`
  Multi-screen UI state model
- `lib/jido_hive_termui_console/nav.ex`
  Screen transitions and room-process lifecycle
- `lib/jido_hive_termui_console/projection.ex`
  Snapshot-to-screen projection helpers
- `lib/jido_hive_termui_console/config.ex`
  Config bootstrap and local room registry
- `lib/jido_hive_termui_console/auth.ex`
  Cached publish auth state
- `lib/jido_hive_termui_console/http.ex`
  Thin `:httpc` boundary
- `lib/jido_hive_termui_console/event_log_poller.ex`
  Short-poll room event task
- `lib/jido_hive_termui_console/escript_bootstrap.ex`
  Escript startup fixes for bundled runtime data and the `ExRatatui` NIF
- `lib/jido_hive_termui_console/screens/`
  Screen-specific rendering and key maps

### Quality gates

From the example directory:

```bash
mix quality
```

From the repo root:

```bash
mix ci
```

Use the repo root gate when you touch multiple apps or shared docs.

### Design constraints that matter in this codebase

- keep room authority on the server
- keep Path A chat submission separate from Path B direct HTTP contribution posts
- derive publish fields from the server publication plan
- use short-poll for the event pane in v1
- avoid pushing graph logic into the UI when the server already owns it

## Troubleshooting

### The lobby is empty and says "No room selected"

On first run, this is expected.

The lobby only shows room ids already saved in `~/.config/hive/rooms.json`. It
does not automatically list every room on the server, and local/prod keep
separate saved room lists.

Use one of these paths:

- press `n` and create a new room through the wizard
- or start with `--room-id <id>` if you already know the room id

Example:

```bash
./hive console --room-id room-123 --participant-id alice
./hive console --prod --room-id room-123 --participant-id alice
```

### The wizard opens but shows no workers

The wizard reads live `/targets` data. If no compatible worker targets are
connected, step 3 now explicitly says `No worker targets available on this
server.` Room creation cannot proceed in that state. Start workers first:

```bash
bin/hive-clients
```

or:

```bash
bin/hive-clients --prod
```

If you are on production and `/targets` is still empty after that, the deployed
environment does not currently have usable worker targets registered.

### The room opens directly but I expected the lobby

The console only skips the lobby when `--room-id <id>` is present.

### The UI opens but shows stale data

Use `Ctrl+R` to refresh and confirm the selected API base is reachable.

### The lobby shows a broken room row

The room id still exists in the saved list for the current server, but that
server returns `404`. Press `d` to remove it from the current server's saved
room list.

### I see `[Render Error]`

Run the console with debug logging enabled:

```bash
./hive console --debug --participant-id alice
```

Then inspect:

```bash
tail -n 100 ~/.config/hive/termui_console.log
```

You can also choose an explicit log file:

```bash
./hive console --debug --log-file /tmp/hive-termui.log --participant-id alice
```

### Publish says auth is missing

Run:

```bash
./hive auth login github
./hive auth login notion
```

Then confirm that `~/.config/hive/credentials.json` contains the expected cached
credential record.

### I need a different server than local or prod

Use:

```bash
./hive console --api-base-url https://your-server.example/api
```

### The example cannot start because the `ExRatatui` native library failed to load

Make sure:

- `mix deps.get` completed successfully
- `mix escript.build` was rerun after dependency changes
- the generated `./hive` file came from this example directory and not an older build artifact

## Related Docs

- [Root README](../../README.md)
- [Server README](../../jido_hive_server/README.md)
- [Client README](../../jido_hive_client/README.md)
