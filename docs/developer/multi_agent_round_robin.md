# Developer Guide: Multi-Agent Round Robin

## Why This Exists

The original demo proved the relay and local execution path, but it still
encoded a two-client story in too many places:

- room payloads hardcoded `architect` and `skeptic`
- default turn counts were fixed
- the operator tooling assumed exactly two client wrappers
- the docs described a specialized protocol instead of the underlying runtime

This guide describes the incremental change that generalized the demo without
turning it into a larger protocol framework.

## Design Goal

The target was an incremental architectural step:

- keep the coordinator authoritative
- keep clients generic
- distribute work across 1 to 39 connected workers
- keep the algorithm intentionally simple
- preserve a clean upgrade path for future coordinator strategies

The current demo is therefore a generalized workload distributor, not a
peer-to-peer collaboration fabric.

## Feature Changes vs Configuration Changes

The implementation deliberately separates feature changes from configuration and
operator changes.

### Feature Changes

These changed the runtime model:

- added `execution_plan` to room state
- locked the selected worker set at room creation
- derived the default turn budget from the locked participant count
- changed coordinator assignment from fixed roles to round-robin worker
  selection plus coordinator-assigned turn roles
- added room-local exclusion for abandoned workers
- ignored late results from abandoned turns

### Configuration And Operator Changes

These changed how the demo is run:

- added `bin/client-worker`
- updated `bin/client` defaults to a generic worker identity
- changed `bin/hive-clients` from role launchers to generic worker fan-out
- changed `setup/hive create-room` and `live-demo` to discover connected relay
  targets
- changed `run-room` to use the locked plan by default when `max_turns` is not
  specified

Keeping those concerns separate made it possible to test the runtime logic
directly while letting the shell tooling stay thin.

## Execution Plan

The execution plan struct defined in
`lib/jido_hive_server/collaboration/execution_plan.ex` is the core of the
change.

It currently stores:

- `strategy`
- `participant_count`
- `planned_turn_count`
- `completed_turn_count`
- `round_robin_index`
- `excluded_target_ids`
- `locked_participants`

The current strategy is intentionally minimal:

`planned_turn_count = participant_count * 3`

The stage mapping is fixed:

- pass 1 through all workers: `proposal`
- pass 2 through all workers: `critique`
- pass 3 through all workers: `resolution`

That gives the demo a visible buildup while remaining predictable enough for
tests and operator tooling.

## Coordinator Role Assignment

Workers no longer imply room roles.

Each worker registers as a generic participant with a generic target. The
coordinator assigns a turn role at dispatch time:

- `proposer`
- `critic`
- `resolver`

That assignment is embedded in the collaboration envelope and echoed back in the
job payload. The worker logs now show both:

- the local client identity
- the assigned role for the current turn

This keeps the worker runtime generic while preserving a structured collaboration
shape for the demo.

## Locked Budget Semantics

The important semantic change is that the room budget is logical, not merely a
count of job attempts.

Example:

- 10 workers selected at room creation
- default plan is 30 completed turns
- one worker drops on turn 7
- the room still targets 30 completed turns, but the remaining workers absorb
  the rest of the schedule

That is why `abandon_turn` does not increment `completed_turn_count`.

The room loop now drives toward a target completed-turn count instead of a raw
attempt counter.

## Drop-Off Handling

Two failure classes mattered for the generalized flow.

### Offline Before Assignment

If a target is already offline when the coordinator is choosing the next worker,
the room simply skips it because `select_next_participant/2` only considers live
targets.

### Drop-Off Or Timeout After Turn Open

If the room has already opened a turn and the worker disappears or never
responds in time:

- the turn is marked `abandoned`
- the target is added to `execution_plan.excluded_target_ids`
- the room continues with the remaining workers

That room-local exclusion is important even if the target is still globally
visible for a brief moment, because it prevents a single bad worker from being
selected repeatedly inside the same room.

## Timeout And Late Result Handling

Two correctness fixes were required to make the generalized budget safe.

### Deadline-Aware Polling

The original polling loop only checked for timeout before sleeping. If the poll
interval exceeded the requested timeout, a late completion could arrive and
still be accepted.

The fix was to:

- compute the remaining deadline on each poll
- sleep for `min(poll_interval, remaining_deadline)`
- fail immediately when the remaining budget reaches zero

### Ignoring Late Results

Once a turn is abandoned, any later `job.result` for that job must be ignored.

`ApplyResult` now only mutates room state when the incoming result matches the
currently running turn. If the room has already advanced past that turn, the
result becomes a no-op.

Without that guard, timed-out workers could still increment the completed-turn
count later and corrupt the room history.

## Operator Surface

The shell tooling now mirrors the runtime model:

- `bin/client-worker --worker-index N` launches one generic worker
- `bin/hive-clients` launches 1, 2, or a custom 1..39 worker set in one terminal
- `setup/hive wait-targets --count N` waits for enough workers
- `setup/hive create-room --participant-count N` locks a subset of the live
  workers
- `setup/hive live-demo` defaults to all connected workers when no explicit
  count is provided

This means the control terminal and the server no longer need to know anything
about `architect` or `skeptic`.

Legacy wrappers still exist for compatibility, but they are no longer the
primary story.

## Why The Coordinator Still Chooses Roles

The coordinator remains authoritative for this slice because it keeps the model
simple:

- workers stay stateless beyond the current prompt plus shared history
- the room can serialize collaboration cleanly
- the operator can reason about the exact planned turn budget
- tests stay deterministic

This is a good midpoint between a toy two-client demo and a more open-ended
multi-agent protocol.

## Clean Extension Paths

The current architecture is intentionally prepared for future strategies.

Clean next steps include:

- new `execution_plan.strategy` values
- dynamic stage counts
- specialized worker capability filters
- coordinator policies that choose subsets by capability or prior output quality
- richer room blocking and recovery policies

Those can now be added without rewriting the operator flow or reverting to
hardcoded participant identities.
