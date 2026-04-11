defmodule JidoHiveWorkerRuntime.RuntimeSnapshotTest do
  use ExUnit.Case, async: true

  alias JidoHiveWorkerRuntime.Runtime.State

  defp runtime_opts do
    [
      workspace_id: "workspace-1",
      user_id: "user-1",
      participant_id: "participant-1",
      participant_role: "analyst",
      target_id: "target-1",
      capability_id: "capability-1",
      workspace_root: "/workspace",
      executor: {JidoHiveWorkerRuntime.Executor.Scripted, [provider: :codex, model: "gpt-5.4"]},
      runtime_id: :asm
    ]
  end

  test "builds an initial snapshot from runtime opts" do
    state = State.new(runtime_opts())
    snapshot = State.snapshot(state)

    assert snapshot.client_id == "workspace-1:target-1"
    assert snapshot.connection_status == :starting
    assert snapshot.identity.workspace_id == "workspace-1"
    assert snapshot.identity.participant_id == "participant-1"
    assert snapshot.identity.provider == "codex"
    assert snapshot.identity.runtime_id == "asm"
    assert snapshot.recent_assignments == []
  end

  test "tracks connection state transitions and reconnect counts" do
    snapshot =
      runtime_opts()
      |> State.new()
      |> State.connection_changed(:ready)
      |> State.connection_changed(:waiting_socket)
      |> State.connection_changed(:ready)
      |> State.snapshot()

    assert snapshot.connection_status == :ready
    assert snapshot.metrics.reconnect_count == 1
  end

  test "tracks assignment lifecycle transitions" do
    assignment = %{
      "assignment_id" => "asn-1",
      "room_id" => "room-1",
      "participant_id" => "participant-1",
      "participant_role" => "analyst"
    }

    contribution = %{
      "status" => "completed",
      "summary" => "completed",
      "execution" => %{"status" => "completed"}
    }

    snapshot =
      runtime_opts()
      |> State.new()
      |> State.connection_changed(:ready)
      |> State.assignment_received(assignment)
      |> State.assignment_started(assignment)
      |> State.assignment_finished(assignment, contribution)
      |> State.snapshot()

    assert snapshot.connection_status == :ready
    assert snapshot.current_assignment == nil
    assert snapshot.metrics.assignments_received == 1
    assert snapshot.metrics.assignments_completed == 1
    assert [%{assignment_id: "asn-1", status: "completed"}] = snapshot.recent_assignments
    assert snapshot.last_error == nil
  end

  test "tracks failed assignments and last_error" do
    assignment = %{"assignment_id" => "asn-2", "room_id" => "room-1"}

    snapshot =
      runtime_opts()
      |> State.new()
      |> State.connection_changed(:ready)
      |> State.assignment_received(assignment)
      |> State.assignment_started(assignment)
      |> State.assignment_failed(assignment, {:runtime_error, :boom})
      |> State.snapshot()

    assert snapshot.connection_status == :ready
    assert snapshot.metrics.assignments_failed == 1
    assert snapshot.last_error.assignment_id == "asn-2"
    assert String.contains?(snapshot.last_error.reason, "runtime_error")
  end
end
