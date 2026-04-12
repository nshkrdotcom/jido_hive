# Jido Hive Context Graph

`jido_hive_context_graph` is the external graph/provenance/workflow projection package for
`jido_hive`.

It exists to keep ontology-specific graph behavior out of the authoritative room engine while
preserving the current operator-facing graph workflows for the client, TUI, and web surfaces.

## Responsibilities

- materialize graph objects from room contributions
- build adjacency and provenance projections
- rebuild duplicate/staleness annotations
- derive workflow summary data from the graph projection

It does not own authoritative room truth. That remains in `jido_hive_server`.
