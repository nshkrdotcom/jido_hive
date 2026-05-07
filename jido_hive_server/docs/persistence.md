# Jido Hive Server Persistence

## Scope

Jido Hive Server owns authoritative room truth, REST, websocket, connector state, and local persistence owner. This document is package-local and is the persistence contract for `jido_hive_server` in `jido_hive`.

## Available Tiers

- `:mickey_mouse`: memory or ref-only default. No restart durability claim.
- `:memory_debug`: memory or ref-only with redacted debug evidence only.
- `:local_restart_safe`: supported only when this package or a named adapter package owns a local durable store and preflight proof.
- `:integration_postgres`: supported only when a named Postgres or AshPostgres adapter and migration proof are configured.
- `:ops_durable`: supported only for Temporal-owning runtime packages after explicit substrate proof.
- `:full_debug_tracked`: supported only when durable storage and redacted debug capture are both explicitly preflighted.

## Default Tier

The default tier is `:mickey_mouse`. It is memory-only or ref-only and is lost on restart unless this package explicitly states that a local durable adapter has been selected by the caller.

## Capture Levels

Supported capture levels are `:off`, `:metadata`, `:refs_only`, `:redacted_debug`, and `:full_debug` when the package explicitly supports full debug. Raw credentials, auth headers, token files, credential bodies, raw prompt bodies, raw provider payload bodies, native auth file content, private keys, session cookies, refresh tokens, access tokens, database URLs with credentials, and object-store signed URLs are always forbidden.

## Supported Adapters

Product-local Ecto SQLite repo owned here. Not a product-surface no-bypass scan target.

## Unsupported Adapters

Unsupported adapter selections fail before mutation. Silent fallback from durable selection to memory is invalid. Product code must not import lower store modules directly to compensate for a missing adapter.

## Configuration Precedence

Configuration is explicit caller data first, package option second, release profile third, and built-in default last. Governed flows do not read process environment, local credential files, provider defaults, singleton clients, or application configuration as authority unless this package names a standalone boot boundary.

## Example Config

```elixir
# Default deterministic profile.
[persistence_profile: :mickey_mouse]

# Redacted in-memory debug profile.
[persistence_profile: :memory_debug, capture_level: :redacted_debug]

# Durable opt-in example. The caller must also pass adapter capability and preflight proof.
[persistence_profile: :integration_postgres]
```

## Test Commands

```bash
cd jido_hive_server && mix test; root mix ci
```

## Lost-On-Restart Claims

`:mickey_mouse` and `:memory_debug` data is lost on BEAM or process restart unless the package explicitly says a local durable adapter was selected. Memory profiles may prove semantics, validation, and receipt shape; they do not prove restart durability.

## Valid Durability Claims

Valid durability claims require explicit profile selection, adapter capability, migration or substrate preflight, redacted evidence, focused tests, repo QC, and a pushed commit. Local room and connector state durability through JidoHiveServer.Repo and package migrations.

## Invalid Durability Claims

Invalid claims include ambient provider credentials, default database reachability, default Temporal reachability, object-store availability without opt-in, network reachability, raw debug capture, raw prompt capture, raw provider payload capture, and product direct lower-store imports.

## Debug Sidecar Behavior

Debug sidecars are disabled by default. When enabled, they are read-only or append-only redacted evidence surfaces. Debug failure must be non-mutating and must not alter authority, lease, run, workflow, store, projection, or product state.

## Redaction Guarantees

Evidence stores opaque refs, stable redacted ids, hashes, bounded metadata, claim-check refs, capture tags, receipt refs, store refs without credentials, and partition refs without secrets. Raw secret and raw payload fields are rejected before persistence or export.

## Migration And Preflight Behavior

priv/repo/migrations owns room event, run, snapshot, target, and connector persistence.

## Phase 12 Migration And Preflight Closeout

- Tier: `:local_restart_safe` for SQLite ownership and `:integration_postgres` only as the shared durable profile token used by overlay tests.
- Schema owner: `JidoHiveServer.Repo`.
- Migration owner: `jido_hive_server/priv/repo/migrations`.
- Migration command: `cd jido_hive_server && mix ecto.migrate` for local development or `JidoHiveServer.Release.migrate/0` for release migration.
- Migration preflight command: `JidoHiveServer.Persistence.preflight(profile: :integration_postgres, migration_proof: :present)`.
- Failure behavior: missing migration proof returns `{:error, {:missing_migration_proof, :jido_hive_server}}` before room, event, run, snapshot, target, or connector mutation.
- Rollback behavior: rollback uses `JidoHiveServer.Release.rollback/2` or an operator-owned SQLite database restore; release claims remain open until post-rollback focused tests are recorded.
- Tagged test command: `cd jido_hive_server && mix test test/jido_hive_server/persistence_preflight_test.exs`.
- Release claim boundary: durable room truth is valid only after migration proof, focused tests, root QC, static scans, and pushed commit evidence are recorded.
