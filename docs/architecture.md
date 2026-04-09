# Architecture

## Overview

`jido_hive` is a split client/server system:

- `jido_hive_server` owns rooms, the relay websocket, room persistence, and the
  coordinator logic
- `jido_hive_client` owns local execution and connects outward to the relay as a
  generic worker

The current demo is a generalized multi-worker slice, not a fixed
architect/skeptic pair anymore. A room can lock between 1 and 39 connected
workers and the coordinator drives a simple round-robin workload across them.

## Runtime Shape

### Server

`jido_hive_server` owns:

- Phoenix HTTP and websocket endpoints
- relay target registration and dispatch
- room creation, execution, persistence, and publication planning
- the execution plan that locks the selected worker set for a room
- the coordinator that assigns turn roles and objectives

The server coordinates work, but it does not execute model calls itself.

### Client

`jido_hive_client` owns:

- the outbound websocket connection
- target registration
- local execution through `RelayWorker`
- session execution through `Jido.Harness -> asm -> ASM`
- provider invocation through the configured local runtime, such as Codex CLI

Each client process is just a generic worker. The server assigns the turn role
for each job.

## Round-Robin Execution Plan

When a room is created, the server builds an `execution_plan` from the selected
participants.

The plan currently uses one strategy:

- `round_robin`

The plan locks:

- the participant list
- the turn budget
- the current round-robin pointer
- room-local exclusions for workers that abandon a turn

The default turn budget is:

`planned_turn_count = participant_count * 3`

That means:

- 1 worker -> 3 planned turns
- 2 workers -> 6 planned turns
- 10 workers -> 30 planned turns
- 39 workers -> 117 planned turns

The coordinator still chooses roles. The workers remain generic.

The three coordinator-assigned stages are:

- `proposal` with assigned role `proposer`
- `critique` with assigned role `critic`
- `resolution` with assigned role `resolver`

The current slice is still intentionally simple: one round-robin pass through
all locked workers for each of those three stages.

## Room Loop

The steady-state room loop is:

1. workers connect to the relay and register `codex.exec.session` targets
2. the operator creates a room from the currently selected connected workers
3. the server locks those workers into an execution plan
4. `run-room` opens one turn at a time
5. the coordinator picks the next available worker in round-robin order
6. the server sends a collaboration envelope plus coordinator directives
7. the worker executes locally and returns structured actions
8. the server merges those actions into room state and moves to the next turn

The collaboration envelope now includes execution-plan metadata such as:

- participant count
- planned turn count
- completed turn count
- turns remaining

## Failure Handling

The plan is a logical budget, not just a raw attempt counter.

If a worker drops before it is selected:

- the coordinator simply skips it because it is no longer in the live target set

If a worker drops or times out after a turn has been opened:

- the turn is marked `abandoned`
- that worker is excluded for the rest of the room
- the logical turn budget is preserved
- the coordinator continues with the remaining live workers

Late results from abandoned turns are ignored so they do not corrupt the room
history or the planned turn count.

If no usable workers remain before the locked plan completes, the room moves to
`blocked`.

## Operator Flow

The intended demo flow is now:

- one control terminal running `bin/hive-control`
- one client terminal running `bin/hive-clients`

`bin/hive-clients` can launch 1, 2, or a custom number of generic workers in a
single terminal. `setup/hive create-room` and `setup/hive live-demo` then lock
either all currently connected workers or an explicit `--participant-count`
subset.

The operator surface is deliberately small:

- `wait-targets --count N`
- `create-room --participant-count N`
- `run-room`
- `live-demo`

If `max_assignments` is omitted, `run-room` uses the locked execution plan by default
instead of a hardcoded demo turn count.

## Current Limits

This is still an incremental slice, not a full agent society.

Current intentional limits:

- the coordinator uses one simple three-stage algorithm
- workers do not negotiate roles with each other
- the collaboration is serialized one turn at a time
- persistence is still app-local SQLite

That is deliberate. The architecture is now generalized enough to support more
than two workers cleanly, while still keeping the demo easy to operate and easy
to extend.
