# jido_hive

`jido_hive` is a non-umbrella monorepo with two separate Mix apps:

- `jido_hive_server`: Phoenix coordination server
- `jido_hive_client`: local ASM-backed executor

The current slice is a real client-server collaboration loop:

- local clients connect outbound and advertise session targets
- the server opens refereed turns and sends a versioned collaboration envelope
- clients execute locally through `Jido.Harness -> asm -> ASM`
- the server persists room snapshots, disputes, and publication runs in SQLite
- GitHub and Notion publication planning and execution go through
  `Jido.Integration.V2`

## Requirements

- Erlang/OTP 28
- Elixir `~> 1.19`
- a working local AI CLI for live runs, such as Codex CLI

## Quick Start

Open four terminals.

Terminal 1:

```bash
bin/server
```

Terminal 2:

```bash
bin/client-architect
```

Terminal 3:

```bash
bin/client-skeptic
```

Terminal 4:

```bash
bin/demo-first-slice
```

That script will:

1. wait for both local targets
2. create a room
3. run the refereed slice
4. print the final room snapshot
5. print the publication plan

For live AI runs, `bin/demo-first-slice` also accepts
`JIDO_HIVE_TURN_TIMEOUT_MS` and defaults to `180000`.

## Manual Flow

List targets:

```bash
curl -sS http://127.0.0.1:4000/api/targets | jq
```

Create a room:

```bash
curl -sS -X POST http://127.0.0.1:4000/api/rooms \
  -H 'content-type: application/json' \
  -d '{
    "room_id": "room-manual-1",
    "brief": "Develop a distributed collaboration protocol for two AI clients.",
    "rules": ["Every objection must target a claim or evidence entry."],
    "participants": [
      {
        "participant_id": "architect",
        "role": "architect",
        "target_id": "target-architect",
        "capability_id": "codex.exec.session"
      },
      {
        "participant_id": "skeptic",
        "role": "skeptic",
        "target_id": "target-skeptic",
        "capability_id": "codex.exec.session"
      }
    ]
  }' | jq
```

Run the room:

```bash
curl -sS -X POST http://127.0.0.1:4000/api/rooms/room-manual-1/run \
  -H 'content-type: application/json' \
  -d '{"max_turns": 6, "turn_timeout_ms": 180000}' | jq
```

Fetch the publication plan:

```bash
curl -sS http://127.0.0.1:4000/api/rooms/room-manual-1/publication_plan | jq
```

## Live GitHub / Notion Path

The server now exposes install and connection endpoints so you can obtain
`connection_id` values inside `jido_hive` itself.

Start a GitHub install:

```bash
curl -sS -X POST http://127.0.0.1:4000/api/connectors/github/installs \
  -H 'content-type: application/json' \
  -d '{
    "tenant_id": "workspace-local",
    "actor_id": "operator-1",
    "auth_type": "oauth2",
    "subject": "octocat",
    "requested_scopes": ["repo"]
  }' | jq
```

Complete that install after exchanging the provider code or token upstream:

```bash
curl -sS -X POST http://127.0.0.1:4000/api/connectors/installs/<install-id>/complete \
  -H 'content-type: application/json' \
  -d '{
    "subject": "octocat",
    "granted_scopes": ["repo"],
    "secret": {"access_token": "REDACTED"}
  }' | jq
```

List current connector connections:

```bash
curl -sS http://127.0.0.1:4000/api/connectors/github/connections?tenant_id=workspace-local | jq
curl -sS http://127.0.0.1:4000/api/connectors/notion/connections?tenant_id=workspace-local | jq
```

Execute publication runs:

```bash
curl -sS -X POST http://127.0.0.1:4000/api/rooms/room-manual-1/publications \
  -H 'content-type: application/json' \
  -d '{
    "channels": ["github", "notion"],
    "connections": {
      "github": "connection-github-1",
      "notion": "connection-notion-1"
    },
    "bindings": {
      "github": {"repo": "owner/repo"},
      "notion": {
        "parent.data_source_id": "data-source-id",
        "title_property": "Name"
      }
    },
    "actor_id": "operator-1",
    "tenant_id": "workspace-local"
  }' | jq
```

Then inspect the durable publication history:

```bash
curl -sS http://127.0.0.1:4000/api/rooms/room-manual-1/publications | jq
```

## Client Env

The repo-level `bin/client` wrapper accepts these useful env vars:

- `JIDO_HIVE_URL`
- `JIDO_HIVE_WORKSPACE_ID`
- `JIDO_HIVE_RELAY_TOPIC`
- `JIDO_HIVE_WORKSPACE_ROOT`
- `PARTICIPANT_ROLE`
- `PARTICIPANT_ID`
- `TARGET_ID`
- `USER_ID`
- `CAPABILITY_ID`
- `JIDO_HIVE_PROVIDER`
- `JIDO_HIVE_MODEL`
- `JIDO_HIVE_TIMEOUT_MS`
- `JIDO_HIVE_CLI_PATH`
- `JIDO_HIVE_TURN_TIMEOUT_MS`

## Notes

- Live provider turns can finish as `publication_ready` or `in_review`
  depending on whether the model actually emits a `PUBLISH` action.
- The client now performs one strict no-tool repair pass when a provider
  returns prose or malformed JSON instead of the room contract.
