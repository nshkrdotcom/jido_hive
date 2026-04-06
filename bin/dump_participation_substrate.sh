#!/bin/bash

# Participation Substrate Dump Script
# Outputs key Elixir files and documentation for the jido_hive participation substrate refactor.

FILES=(
  # Documentation
  "../jido_brainstorm/nshkrdotcom/docs/20260405/jido_hive_participation_substrate/implementation_checklist.md"
  
  # Server - Data Model (Phase 1)
  "jido_hive_server/lib/jido_hive_server/collaboration/schema/participant.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/schema/assignment.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/schema/context_object.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/schema/contribution.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/schema/room_event.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/schema/room_command.ex"

  # Server - Core Collaboration & State (Phase 2)
  "jido_hive_server/lib/jido_hive_server/collaboration.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/room_server.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/room_agent.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/event_reducer.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/room_timeline.ex"
  
  # Server - Dispatch Policies (Phase 2)
  "jido_hive_server/lib/jido_hive_server/collaboration/dispatch_policy.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/dispatch_policy/registry.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/dispatch_policies/round_robin.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/dispatch_policies/resource_pool.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/dispatch_policies/human_gate.ex"

  # Server - Context Queries & Views (Phase 2)
  "jido_hive_server/lib/jido_hive_server/collaboration/context_query.ex"
  "jido_hive_server/lib/jido_hive_server/collaboration/context_view.ex"

  # Server - Boundaries & API Controllers (Phase 3)
  "jido_hive_server/lib/jido_hive_server/collaboration/protocol_codec.ex"
  "jido_hive_server/lib/jido_hive_server_web/relay_channel.ex"
  "jido_hive_server/lib/jido_hive_server_web/router.ex"
  "jido_hive_server/lib/jido_hive_server_web/controllers/policies_controller.ex"
  "jido_hive_server/lib/jido_hive_server_web/controllers/room_context_controller.ex"
  "jido_hive_server/lib/jido_hive_server_web/controllers/room_contribution_controller.ex"
  "jido_hive_server/lib/jido_hive_server_web/controllers/room_timeline_controller.ex"
  
  # Client - Core Execution & Boundaries (Phase 4)
  "jido_hive_client/lib/jido_hive_client/runtime.ex"
  "jido_hive_client/lib/jido_hive_client/runtime/state.ex"
  "jido_hive_client/lib/jido_hive_client/executor.ex"
  "jido_hive_client/lib/jido_hive_client/executor/session.ex"
  "jido_hive_client/lib/jido_hive_client/executor/projection.ex"
  "jido_hive_client/lib/jido_hive_client/collaboration_prompt.ex"
  "jido_hive_client/lib/jido_hive_client/execution_contract.ex"
  "jido_hive_client/lib/jido_hive_client/result_decoder.ex"
  "jido_hive_client/lib/jido_hive_client/relay_worker.ex"
  "jido_hive_client/lib/jido_hive_client/boundary/protocol_codec.ex"
  
  # Client - Control (Phase 4)
  "jido_hive_client/lib/jido_hive_client/control/server.ex"
  "jido_hive_client/lib/jido_hive_client/control/router.ex"
)

for file in "${FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "--- FILE: $file ---"
    cat "$file"
    echo -e "\n--- END FILE ---\n"
  else
    echo "--- WARNING: File not found: $file ---"
  fi
done
