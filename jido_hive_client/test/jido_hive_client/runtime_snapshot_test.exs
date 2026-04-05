defmodule JidoHiveClient.RuntimeSnapshotTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Runtime.State

  defp runtime_opts do
    [
      workspace_id: "workspace-1",
      user_id: "user-1",
      participant_id: "participant-1",
      participant_role: "architect",
      target_id: "target-1",
      capability_id: "capability-1",
      workspace_root: "/workspace",
      executor: {JidoHiveClient.Executor.Scripted, [provider: :codex, model: "gpt-5.4"]},
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
    assert snapshot.recent_jobs == []
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

  test "tracks job lifecycle transitions" do
    job = %{
      "job_id" => "job-1",
      "room_id" => "room-1",
      "participant_id" => "participant-1",
      "participant_role" => "architect"
    }

    result = %{
      "status" => "completed",
      "summary" => "completed",
      "execution" => %{"status" => "completed"}
    }

    snapshot =
      runtime_opts()
      |> State.new()
      |> State.connection_changed(:ready)
      |> State.job_received(job)
      |> State.job_started(job)
      |> State.job_finished(job, result)
      |> State.snapshot()

    assert snapshot.connection_status == :ready
    assert snapshot.current_job == nil
    assert snapshot.metrics.jobs_received == 1
    assert snapshot.metrics.jobs_completed == 1
    assert [%{job_id: "job-1", status: "completed"}] = snapshot.recent_jobs
    assert snapshot.last_error == nil
  end

  test "tracks failed jobs and last_error" do
    job = %{"job_id" => "job-2", "room_id" => "room-1"}

    snapshot =
      runtime_opts()
      |> State.new()
      |> State.connection_changed(:ready)
      |> State.job_received(job)
      |> State.job_started(job)
      |> State.job_failed(job, {:runtime_error, :boom})
      |> State.snapshot()

    assert snapshot.connection_status == :ready
    assert snapshot.metrics.jobs_failed == 1
    assert snapshot.last_error.job_id == "job-2"
    assert String.contains?(snapshot.last_error.reason, "runtime_error")
  end
end
