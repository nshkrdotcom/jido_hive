# Jido Hive Publications

`jido_hive_publications` owns publication planning, execution, run persistence,
and publication-specific workspace models.

It is an explicit extension package over canonical room resources. It depends on:

- `jido_hive_client` for canonical room fetches and auth-state helpers
- `jido_hive_context_graph` for graph-aware projection inputs
- `jido_hive_server` for the shared server repo and database configuration

The base room engine and the base surface do not own publication workflows after
the big-bang cutover.
