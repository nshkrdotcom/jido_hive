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

Start the local stack in separate terminals:

```bash
bin/server
bin/client-architect
bin/client-skeptic
```

Check that the server is up and the targets are visible:

```bash
setup/hive doctor
```

Create and run a room:

```bash
setup/hive create-room room-manual-1
setup/hive run-room room-manual-1 --turn-timeout-ms 180000
setup/hive publication-plan room-manual-1
```

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
