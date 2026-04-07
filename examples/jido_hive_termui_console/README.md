# Jido Hive TermUI Console

`jido_hive_termui_console` is the first formal product consumer of the `jido_hive_client` embedded runtime.

It is a terminal UI built with `term_ui` and intended to prove the human-first collaboration flow:

- left pane: conversation timeline
- right pane: live structured context
- bottom input: normal chat message entry

The backing server surfaces now include derived stale-context flags plus contradiction and invalidation timeline events, so the example can pick those up without a separate server API expansion.

The local `term_ui` framework source and examples used for this project live at:

- `/home/home/p/g/n/term_ui`
- `/home/home/p/g/n/term_ui/guides/user`
- `/home/home/p/g/n/term_ui/examples`

## Run locally

```bash
cd /home/home/p/g/n/jido_hive/examples/jido_hive_termui_console
mix deps.get
mix run -- --room-id room-123 --participant-id alice
```

Options:

- `--api-base-url` default: `http://127.0.0.1:4000/api`
- `--room-id` required
- `--participant-id` default: `human-local`
- `--participant-role` default: `collaborator`
- `--poll-interval-ms` default: `500`

## Keys

- `Enter`: submit the current input buffer as chat
- `Up/Down`: move context selection
- `Ctrl+A`: accept the selected context object into a binding decision
- `Ctrl+R`: refresh immediately
- `Ctrl+Q`: quit
