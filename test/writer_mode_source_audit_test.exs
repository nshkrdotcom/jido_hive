defmodule JidoHive.WriterModeSourceAuditTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("..", __DIR__)

  test "room truth is server serialized through RoomServer and EventReducer" do
    room_server = source!("jido_hive_server/lib/jido_hive_server/collaboration/room_server.ex")

    event_reducer =
      source!("jido_hive_server/lib/jido_hive_server/collaboration/event_reducer.ex")

    persistence = source!("jido_hive_server/lib/jido_hive_server/persistence.ex")

    assert room_server =~ "use GenServer"
    assert room_server =~ "GenServer.call(server, {:submit_contribution, attrs})"
    assert room_server =~ "EventReducer.apply_event(snapshot, event)"

    assert room_server =~
             "Persistence.persist_room_transition(snapshot.room.id, events, snapshot)"

    assert room_server =~ "snapshot.clocks.next_event_sequence"

    assert event_reducer =~ "defp reduce_event(snapshot, %RoomEvent{type: :contribution_submitted"
    assert event_reducer =~ "defp reduce_event(snapshot, %RoomEvent{type: :assignment_completed"
    assert event_reducer =~ "defp advance_event_clock"

    assert persistence =~ "persist_room_transition"
    assert persistence =~ "Enum.each(events, fn %RoomEvent{} = event ->"
    assert persistence =~ "conflict_target: :room_id"
  end

  test "client room session state is local and submits intent through the room API" do
    room_session = source!("jido_hive_client/lib/jido_hive_client/room_session.ex")
    session_state = source!("jido_hive_client/lib/jido_hive_client/session_state.ex")
    embedded = source!("jido_hive_client/lib/jido_hive_client/embedded.ex")
    room_api = source!("jido_hive_client/lib/jido_hive_client/boundary/room_api.ex")

    assert room_session =~ "alias JidoHiveClient.Embedded"

    assert room_session =~
             "def submit_chat(session, attrs), do: Embedded.submit_chat(session, attrs)"

    assert session_state =~ "connection_status"
    assert session_state =~ "events_recorded"
    assert embedded =~ "state.room_api.submit_contribution"
    assert room_api =~ "@callback submit_contribution(keyword(), String.t(), map())"

    refute room_session =~ "JidoHiveServer.Persistence"
    refute session_state =~ "JidoHiveServer.Persistence"
    refute embedded =~ "JidoHiveServer.Persistence"
  end

  test "worker runtime state is worker local and cannot mutate room truth directly" do
    runtime_state =
      source!("jido_hive_worker_runtime/lib/jido_hive_worker_runtime/runtime/state.ex")

    relay_worker =
      source!("jido_hive_worker_runtime/lib/jido_hive_worker_runtime/relay_worker.ex")

    server_api =
      source!("jido_hive_worker_runtime/lib/jido_hive_worker_runtime/boundary/server_api.ex")

    assert runtime_state =~ "current_assignment"
    assert runtime_state =~ "recent_assignments"
    assert runtime_state =~ "assignments_completed"
    assert relay_worker =~ "push_contribution(state, room_id, contribution)"
    assert server_api =~ "@callback list_rooms"
    assert server_api =~ "@callback list_room_events"
    assert server_api =~ "@callback upsert_target"

    refute runtime_state =~ "JidoHiveServer.Persistence"
    refute relay_worker =~ "JidoHiveServer.Persistence"
    refute server_api =~ "RoomServer"
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

    assert context_graph_readme =~ "does not own authoritative room truth"
    refute source_text =~ "collaborative_document"
    refute source_text =~ "CRDT"
    refute source_text =~ "operation log"
    refute source_text =~ "causal metadata"
  end

  defp source!(relative_path) do
    @repo_root
    |> Path.join(relative_path)
    |> File.read!()
  end
end
