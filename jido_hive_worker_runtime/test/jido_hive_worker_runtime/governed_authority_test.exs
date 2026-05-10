defmodule JidoHiveWorkerRuntime.GovernedAuthorityTest do
  use ExUnit.Case, async: false

  alias JidoHiveWorkerRuntime.{CLI, Runtime}

  test "governed worker CLI materializes worker and provider options from authority only" do
    assert {:ok, opts} =
             CLI.run([
               "--governed-authority-ref",
               "auth-worker-1",
               "--governed-worker-ref",
               "worker-ref-1",
               "--governed-credential-ref",
               "cred-worker-1",
               "--governed-provider",
               "claude",
               "--governed-model",
               "claude-opus",
               "--governed-reasoning-effort",
               "medium",
               "--governed-control-port",
               "4555",
               "--governed-control-host",
               "127.0.0.2",
               "--log-level",
               "info"
             ])

    assert Keyword.fetch!(opts, :governed_authority_ref) == "auth-worker-1"
    assert Keyword.fetch!(opts, :credential_ref) == "cred-worker-1"
    assert Keyword.fetch!(opts, :participant_id) == "worker-ref-1"
    assert Keyword.fetch!(opts, :control_port) == 4555
    assert Keyword.fetch!(opts, :control_host) == "127.0.0.2"
    assert Keyword.fetch!(opts, :log_level) == :info

    assert {JidoHiveWorkerRuntime.Executor.Session, executor_opts} =
             Keyword.fetch!(opts, :executor)

    assert Keyword.fetch!(executor_opts, :provider) == :claude
    assert Keyword.fetch!(executor_opts, :model) == "claude-opus"
    assert Keyword.fetch!(executor_opts, :reasoning_effort) == :medium
    assert Keyword.fetch!(executor_opts, :credential_ref) == "cred-worker-1"
  end

  test "governed worker CLI rejects direct singleton runtime fields" do
    assert CLI.run([
             "--governed-authority-ref",
             "auth-worker-1",
             "--governed-worker-ref",
             "worker-ref-1",
             "--governed-credential-ref",
             "cred-worker-1",
             "--provider",
             "codex"
           ]) == {:error, {:governed_direct_worker_field, :provider}}
  end

  test "runtime event log and snapshot redact governed materialized secrets" do
    {:ok, runtime} =
      Runtime.start_link(
        governed_authority_ref: "auth-worker-1",
        redaction_values: ["env-secret-worker"],
        executor: JidoHiveWorkerRuntime.Executor.Scripted
      )

    :ok =
      Runtime.assignment_failed(runtime, %{"id" => "asn-1", "room_id" => "room-1"}, %{
        error: "env-secret-worker"
      })

    snapshot = Runtime.snapshot(runtime)
    events = Runtime.recent_events(runtime)

    assert String.contains?(snapshot.last_error.reason, "[REDACTED]")
    refute String.contains?(snapshot.last_error.reason, "env-secret-worker")

    assert [%{payload: %{"reason" => event_reason}}] = events
    assert String.contains?(event_reason, "[REDACTED]")
    refute String.contains?(event_reason, "env-secret-worker")
  end
end
