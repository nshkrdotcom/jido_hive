# Jido Hive Product No-Bypass

## Boundary

Jido Hive product-facing packages are the client, shared surface, web UI, Switchyard TUI, and examples. Server, publication, and worker-runtime packages are owner scopes and must carry their own persistence docs instead of being scanned as product surfaces.

## Verification

Scan scope: `jido_hive_client/lib/**/*.ex`, `jido_hive_surface/lib/**/*.ex`, `jido_hive_web/lib/**/*.ex`, `jido_hive_switchyard_tui/lib/**/*.ex`, and `examples/**/*.ex`. Store-owner packages are explicit exclusions, not silent passes.

## Owner Package Exclusions

A package may be excluded from product-surface scanning only when it owns the local store, connector adapter, or runtime integration being excluded. The package must document its adapter, default tier, durable opt-in, migration or preflight, allowed consumer surface, and redaction guarantees in package-local `docs/persistence.md`.

## Forbidden Product Imports

Product surfaces must not import lower runtime, lower store, trace writer, provider SDK, generated SDK, database repo, object store, or Temporal client modules directly. Add an AppKit surface or lower contract first.
