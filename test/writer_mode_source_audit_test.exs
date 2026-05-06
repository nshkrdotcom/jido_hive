defmodule JidoHive.WriterModeSourceAuditTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("..", __DIR__)

  test "room truth is server serialized through RoomServer and EventReducer" do
    room_server = source!("jido_hive_server/lib/jido_hive_server/collaboration/room_server.ex")

    event_reducer =
      source!("jido_hive_server/lib/jido_hive_server/collaboration/event_reducer.ex")

    persistence = source!("jido_hive_server/lib/jido_hive_server/persistence.ex")

    assert String.contains?(room_server, "use GenServer")
    assert String.contains?(room_server, "GenServer.call(server, {:submit_contribution, attrs})")
    assert String.contains?(room_server, "EventReducer.apply_event(snapshot, event)")

    assert String.contains?(
             room_server,
             "Persistence.persist_room_transition(snapshot.room.id, events, snapshot)"
           )

    assert String.contains?(room_server, "snapshot.clocks.next_event_sequence")

    assert String.contains?(
             event_reducer,
             "defp reduce_event(snapshot, %RoomEvent{type: :contribution_submitted"
           )

    assert String.contains?(
             event_reducer,
             "defp reduce_event(snapshot, %RoomEvent{type: :assignment_completed"
           )

    assert String.contains?(event_reducer, "defp advance_event_clock")

    assert String.contains?(persistence, "persist_room_transition")
    assert String.contains?(persistence, "Enum.each(events, fn %RoomEvent{} = event ->")
    assert String.contains?(persistence, "conflict_target: :room_id")
  end

  test "client room session state is local and submits intent through the room API" do
    room_session = source!("jido_hive_client/lib/jido_hive_client/room_session.ex")
    session_state = source!("jido_hive_client/lib/jido_hive_client/session_state.ex")
    embedded = source!("jido_hive_client/lib/jido_hive_client/embedded.ex")
    room_api = source!("jido_hive_client/lib/jido_hive_client/boundary/room_api.ex")

    assert String.contains?(room_session, "alias JidoHiveClient.Embedded")

    assert String.contains?(
             room_session,
             "def submit_chat(session, attrs), do: Embedded.submit_chat(session, attrs)"
           )

    assert String.contains?(session_state, "connection_status")
    assert String.contains?(session_state, "events_recorded")
    assert String.contains?(embedded, "state.room_api.submit_contribution")

    assert String.contains?(
             room_api,
             "@callback submit_contribution(keyword(), String.t(), map())"
           )

    refute String.contains?(room_session, "JidoHiveServer.Persistence")
    refute String.contains?(session_state, "JidoHiveServer.Persistence")
    refute String.contains?(embedded, "JidoHiveServer.Persistence")
  end

  test "worker runtime state is worker local and cannot mutate room truth directly" do
    runtime_state =
      source!("jido_hive_worker_runtime/lib/jido_hive_worker_runtime/runtime/state.ex")

    relay_worker =
      source!("jido_hive_worker_runtime/lib/jido_hive_worker_runtime/relay_worker.ex")

    server_api =
      source!("jido_hive_worker_runtime/lib/jido_hive_worker_runtime/boundary/server_api.ex")

    assert String.contains?(runtime_state, "current_assignment")
    assert String.contains?(runtime_state, "recent_assignments")
    assert String.contains?(runtime_state, "assignments_completed")
    assert String.contains?(relay_worker, "push_contribution(state, room_id, contribution)")
    assert String.contains?(server_api, "@callback list_rooms")
    assert String.contains?(server_api, "@callback list_room_events")
    assert String.contains?(server_api, "@callback upsert_target")

    refute String.contains?(runtime_state, "JidoHiveServer.Persistence")
    refute String.contains?(relay_worker, "JidoHiveServer.Persistence")
    refute String.contains?(server_api, "RoomServer")
  end

  test "context graph is a derived projection and source does not claim OT or CRDT ownership" do
    context_graph_readme = source!("jido_hive_context_graph/README.md")

    source_text =
      [
        "jido_hive_server/lib",
        "jido_hive_client/lib",
        "jido_hive_worker_runtime/lib",
        "jido_hive_context_graph/lib"
      ]
      |> Enum.flat_map(&Path.wildcard(Path.join(@repo_root, "#{&1}/**/*.{ex,exs}")))
      |> Enum.map(&File.read!/1)
      |> Enum.join("\n")

    assert String.contains?(context_graph_readme, "does not own authoritative room truth")
    refute String.contains?(source_text, "collaborative_document")
    refute String.contains?(source_text, "CRDT")
    refute String.contains?(source_text, "operation log")
    refute String.contains?(source_text, "causal metadata")
  end

  defp source!(relative_path) do
    @repo_root
    |> Path.join(relative_path)
    |> File.read!()
  end
end
