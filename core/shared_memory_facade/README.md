# Jido Hive Shared Memory Facade

Explicit shared-memory grants over governed memory scopes. The facade validates
read, write, handoff, and revocation grants before accepting shared-memory
operations and never projects raw memory bodies or skill private state.

## Persistence Documentation

See `docs/persistence.md` for tiers, defaults, adapters, unsupported selections, config examples, restart claims, durability claims, debug sidecar behavior, redaction guarantees, migration or preflight behavior, and no-bypass scope when applicable.
