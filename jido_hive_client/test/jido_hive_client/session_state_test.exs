defmodule JidoHiveClient.SessionStateTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.SessionState

  defp session_opts do
    [
      workspace_id: "workspace-1",
      user_id: "user-1",
      participant_id: "participant-1",
      participant_role: "coordinator",
      participant_kind: "human",
      target_id: "target-1",
      capability_id: "human.chat",
      workspace_root: "/workspace",
      room_id: "room-1"
    ]
  end

  test "builds an initial embedded session snapshot from opts" do
    state = SessionState.new(session_opts())
    snapshot = SessionState.snapshot(state)

    assert snapshot.session_id == "workspace-1:room-1:participant-1"
    assert snapshot.connection_status == :starting
    assert snapshot.identity.workspace_id == "workspace-1"
    assert snapshot.identity.participant_id == "participant-1"
    assert snapshot.identity.participant_kind == "human"
    assert snapshot.metadata.mode == "embedded"
    assert snapshot.metadata.room_id == "room-1"
    assert snapshot.metrics.events_recorded == 0
  end

  test "tracks connection state transitions and reconnect counts" do
    snapshot =
      session_opts()
      |> SessionState.new()
      |> SessionState.connection_changed(:ready, %{"mode" => "embedded", "room_id" => "room-1"})
      |> SessionState.connection_changed(:stopped, %{})
      |> SessionState.connection_changed(:ready, %{"mode" => "embedded", "room_id" => "room-1"})
      |> SessionState.snapshot()

    assert snapshot.connection_status == :ready
    assert snapshot.metadata.room_id == "room-1"
    assert snapshot.metrics.reconnect_count == 1
  end

  test "tracks recorded session events and clears last_error on ready" do
    snapshot =
      session_opts()
      |> SessionState.new()
      |> SessionState.put_error(:timeout)
      |> SessionState.record_event(%{type: "embedded.sync.failed"})
      |> SessionState.connection_changed(:ready, %{"room_id" => "room-1"})
      |> SessionState.snapshot()

    assert snapshot.metrics.events_recorded == 1
    assert snapshot.connection_status == :ready
    assert snapshot.last_error == nil
  end
end
