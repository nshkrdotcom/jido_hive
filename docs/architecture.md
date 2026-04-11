# Architecture

## Overview

`jido_hive` is a split system with four primary package boundaries:

- `jido_hive_server`
  authoritative room truth, relay, persistence, context graph, publications
- `jido_hive_client`
  reusable operator workflows, room-scoped local session behavior, headless CLI
- `jido_hive_worker_runtime`
  relay workers, assignment execution, worker control API, runtime bootstrap
- Switchyard packages plus the example console
  terminal rendering and operator workflow presentation over the client seams

The important rule is:

- the server decides what the room is
- the client decides how operator and room-session consumers talk to that room
- the worker runtime executes assignments against that room
- the TUI renders those seams; it does not redefine them

## Runtime shape

### Server

`jido_hive_server` owns:

- Phoenix HTTP and websocket endpoints
- room creation, execution, persistence, and publication planning
- relay target registration and assignment dispatch
- context graph projection and workflow summary generation
- connector install and connection state

The server coordinates work, but it does not execute model turns itself.

### Operator client

`jido_hive_client` owns:

- HTTP-backed room inspection and mutation workflows
- room-scoped local human session behavior
- headless JSON CLI for scripts and bug reproduction
- shared workflow/focus/provenance derivations consumed by Switchyard

It does not own relay workers or assignment execution.

### Worker runtime

`jido_hive_worker_runtime` owns:

- outbound websocket relay participation
- target registration
- local assignment execution
- prompt shaping and contribution normalization
- worker-local assignment state and event history
- worker escript bootstrap for `tzdata` and `erlexec`

Each worker process is generic. The server assigns role and objective per turn.

### TUI

Switchyard plus the Jido Hive Switchyard packages own:

- terminal layout
- key handling
- routing and overlays
- selected-object presentation
- composition of operator flows over `jido_hive_client`

They do not own authoritative room semantics.

## Room loop

The steady-state room loop is:

1. worker runtimes connect to the relay and register `workspace.exec.session`
   targets
2. the operator creates a room from a selected worker set
3. the server locks those workers into a room execution plan
4. a run operation opens one assignment at a time
5. the server chooses the next participant according to dispatch policy
6. the server sends an assignment envelope over the relay
7. the worker runtime executes locally and returns a structured contribution
8. the server reduces that contribution into room truth
9. operator surfaces inspect or steer the same room through API and client seams

## Transport split

There are two primary transport styles:

- operator flows use the HTTP API
- worker runtime flows use the websocket relay

That means:

- `setup/hive`, `jido_hive_client`, and the Switchyard-backed console are
  HTTP-backed for room/operator work
- `bin/client` and `bin/client-worker` launch websocket relay workers through
  `jido_hive_worker_runtime`

## Failure handling

### Operator-side failures

If a room inspection or mutation fails:

- debug the server response first
- reproduce via `jido_hive_client` second
- only then inspect Switchyard/TUI behavior

### Worker-side failures

If a worker drops or execution fails:

- the room reducer records the assignment failure
- the room may continue with remaining live workers depending on policy/state
- late results from abandoned turns must not corrupt room history

## Current limits

Current intentional limits:

- room collaboration is still serialized one assignment at a time
- persistence is still app-local SQLite
- policy space is still small compared with the long-term control-plane vision

Those are acceptable current constraints. The important architectural move is
that operator/session code and worker execution code are now separate packages.
