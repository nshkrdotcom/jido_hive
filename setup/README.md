# Setup Toolkit

`setup/hive` is the user-facing shell wrapper for the live operator flow.

It removes the raw `curl`/JSON payload boilerplate for:

- checking the local server state
- creating and running rooms
- inspecting publication plans and publication history
- starting and completing GitHub / Notion connector installs
- listing live connector connections
- executing publication runs

## Requirements

- `curl`
- `jq`
- a running `jido_hive` server, usually through `bin/server`

By default the toolkit talks to `http://127.0.0.1:4000/api`.

You can override that with:

```bash
export JIDO_HIVE_API_BASE=http://127.0.0.1:4100/api
```

These defaults are also configurable:

```bash
export JIDO_HIVE_TENANT_ID=workspace-local
export JIDO_HIVE_ACTOR_ID=operator-1
export JIDO_HIVE_GITHUB_SUBJECT=octocat
export JIDO_HIVE_NOTION_SUBJECT=notion-workspace
```

## Quick Flow

The fast path is three commands in three terminals:

```bash
bin/live-demo-server
bin/client-architect
bin/client-skeptic
```

That is enough for a developer to get a real collaborative run. The server
wrapper waits for both clients, creates the room, runs the slice, and prints the
room snapshot plus publication plan.

If you already have live connection ids, set these before `bin/live-demo-server`
to auto-publish as part of the same flow:

```bash
export JIDO_HIVE_GITHUB_CONNECTION=connection-github-1
export JIDO_HIVE_GITHUB_REPO=owner/repo
export JIDO_HIVE_NOTION_CONNECTION=connection-notion-1
export JIDO_HIVE_NOTION_DATA_SOURCE_ID=data-source-id
export JIDO_HIVE_NOTION_TITLE_PROPERTY=Name
export JIDO_HIVE_AUTO_PUBLISH=1
```

## Manual Operator Flow

Wait for the server and both clients:

```bash
setup/hive wait-server
setup/hive wait-targets
```

Create and run a room:

```bash
setup/hive live-demo --room-id room-manual-1
```

That command waits for the stack, creates or reuses the room, runs the
collaboration loop, and prints the room snapshot plus publication plan.

## GitHub Install

Start the install:

```bash
setup/hive start-install github --subject octocat --scope repo
```

That returns JSON with the install record. Copy the `data.id` value, complete the
provider-side exchange manually, then finish the install:

```bash
setup/hive complete-install <install-id> --subject octocat --scope repo
```

If `JIDO_HIVE_ACCESS_TOKEN` is not set, the script will prompt for the access
token without echoing it.

List current GitHub connections:

```bash
setup/hive connections github
```

## Notion Install

Start the install:

```bash
setup/hive start-install notion --subject notion-workspace
```

Complete it after the upstream OAuth or token exchange:

```bash
setup/hive complete-install <install-id> --subject notion-workspace
```

List current Notion connections:

```bash
setup/hive connections notion
```

## Publication Execution

GitHub only:

```bash
setup/hive publish room-manual-1 \
  --github-connection connection-github-1 \
  --github-repo owner/repo
```

Notion only:

```bash
setup/hive publish room-manual-1 \
  --notion-connection connection-notion-1 \
  --notion-data-source-id data-source-id
```

GitHub and Notion together:

```bash
setup/hive publish room-manual-1 \
  --github-connection connection-github-1 \
  --github-repo owner/repo \
  --notion-connection connection-notion-1 \
  --notion-data-source-id data-source-id \
  --notion-title-property Name
```

Inspect durable publication history:

```bash
setup/hive publication-runs room-manual-1
```

## Command Reference

Show help:

```bash
setup/hive help
```

Wait for the server:

```bash
setup/hive wait-server
```

Wait for the default architect and skeptic targets:

```bash
setup/hive wait-targets
```

Fetch a room snapshot:

```bash
setup/hive room room-manual-1
```

List targets:

```bash
setup/hive targets
```

Show an install record:

```bash
setup/hive show-install <install-id>
```
