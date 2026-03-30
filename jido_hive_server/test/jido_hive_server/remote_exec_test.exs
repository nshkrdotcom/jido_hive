defmodule JidoHiveServer.RemoteExecTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias Jido.Integration.V2.BoundaryCapability
  alias Jido.Integration.V2
  alias Jido.Integration.V2.TargetDescriptor
  alias JidoHiveServer.RemoteExec

  test "registers relay connection and target metadata for observability" do
    channel_pid = self()
    on_exit(fn -> :ok = RemoteExec.remove_channel(channel_pid) end)

    assert {:ok, connection} =
             RemoteExec.register_connection(channel_pid, %{
               "workspace_id" => "workspace-observable",
               "user_id" => "user-observable",
               "participant_id" => "architect",
               "participant_role" => "architect"
             })

    assert connection.workspace_id == "workspace-observable"
    assert connection.user_id == "user-observable"
    assert connection.participant_id == "architect"
    assert connection.participant_role == "architect"
    assert String.starts_with?(connection.connection_id, "conn-")

    assert {:ok, target} =
             RemoteExec.upsert_target(channel_pid, %{
               "workspace_id" => "workspace-observable",
               "user_id" => "user-observable",
               "participant_id" => "architect",
               "participant_role" => "architect",
               "target_id" => "target-observable",
               "capability_id" => "codex.exec.session",
               "runtime_driver" => "asm",
               "provider" => "codex",
               "workspace_root" => "/tmp/jido_hive_observable",
               "execution_surface" => %{
                 "surface_kind" => "ssh_exec",
                 "transport_options" => %{"destination" => "builder.example"}
               },
               "execution_environment" => %{
                 "workspace_root" => "/tmp/jido_hive_observable",
                 "allowed_tools" => ["git.status"]
               },
               "provider_options" => %{"model" => "gpt-5.4", "reasoning_effort" => "low"}
             })

    assert target.workspace_id == "workspace-observable"
    assert target.participant_id == "architect"
    assert target.participant_role == "architect"
    assert target.target_id == "target-observable"
    assert target.capability_id == "codex.exec.session"
    assert target.provider == "codex"
    assert target.execution_surface["surface_kind"] == "ssh_exec"
    assert target.execution_environment["workspace_root"] == "/tmp/jido_hive_observable"
    assert target.provider_options["model"] == "gpt-5.4"

    assert {:ok, fetched_target} = RemoteExec.fetch_target("target-observable")
    assert fetched_target.participant_id == "architect"
    assert fetched_target.capability_id == "codex.exec.session"
    assert fetched_target.execution_surface["surface_kind"] == "ssh_exec"
    assert fetched_target.execution_environment["allowed_tools"] == ["git.status"]
    assert fetched_target.provider_options["reasoning_effort"] == "low"
  end

  test "removing a channel retracts its session target from the V2 projection" do
    channel_pid = self()

    assert {:ok, _connection} =
             RemoteExec.register_connection(channel_pid, %{
               "workspace_id" => "workspace-cleanup",
               "user_id" => "user-cleanup",
               "participant_id" => "cleanup",
               "participant_role" => "architect"
             })

    assert {:ok, _target} =
             RemoteExec.upsert_target(channel_pid, %{
               "workspace_id" => "workspace-cleanup",
               "user_id" => "user-cleanup",
               "participant_id" => "cleanup",
               "participant_role" => "architect",
               "target_id" => "target-cleanup",
               "capability_id" => "codex.exec.session",
               "runtime_driver" => "asm",
               "provider" => "codex",
               "workspace_root" => "/tmp/jido_hive_cleanup"
             })

    assert target_ids_for("codex.exec.session") |> Enum.member?("target-cleanup")

    assert :ok = RemoteExec.remove_channel(channel_pid)
    refute Enum.any?(RemoteExec.list_targets(), &(&1.target_id == "target-cleanup"))
    refute target_ids_for("codex.exec.session") |> Enum.member?("target-cleanup")
  end

  test "projects boundary-capable relay targets through the standardized target extension" do
    channel_pid = self()
    on_exit(fn -> :ok = RemoteExec.remove_channel(channel_pid) end)

    assert {:ok, _connection} =
             RemoteExec.register_connection(channel_pid, %{
               "workspace_id" => "workspace-boundary",
               "user_id" => "user-boundary",
               "participant_id" => "worker-boundary",
               "participant_role" => "worker"
             })

    assert {:ok, _target} =
             RemoteExec.upsert_target(channel_pid, %{
               "workspace_id" => "workspace-boundary",
               "user_id" => "user-boundary",
               "participant_id" => "worker-boundary",
               "participant_role" => "worker",
               "target_id" => "target-boundary",
               "capability_id" => "codex.exec.session",
               "runtime_driver" => "asm",
               "provider" => "codex",
               "workspace_root" => "/srv/hive",
               "boundary_capability" => %{
                 "supported" => true,
                 "boundary_classes" => ["leased_cell"],
                 "attach_modes" => ["guest_bridge"],
                 "checkpointing" => false
               },
               "boundary_request" => %{
                 "boundary_session_id" => "bnd-target-boundary",
                 "backend_kind" => "microvm",
                 "boundary_class" => "leased_cell",
                 "attach" => %{"mode" => "attachable", "working_directory" => "/srv/hive"},
                 "refs" => %{
                   "target_id" => "target-boundary",
                   "runtime_ref" => "runtime-target-boundary",
                   "correlation_id" => "corr-target-boundary",
                   "request_id" => "req-target-boundary"
                 }
               }
             })

    assert {:ok, %TargetDescriptor{} = descriptor} = V2.fetch_target("target-boundary")

    assert TargetDescriptor.authored_boundary_capability(descriptor) ==
             BoundaryCapability.new!(%{
               supported: true,
               boundary_classes: ["leased_cell"],
               attach_modes: ["guest_bridge"],
               checkpointing: false
             })
  end

  test "projects boundary-capable relay targets from reopen metadata through the standardized target extension" do
    channel_pid = self()
    on_exit(fn -> :ok = RemoteExec.remove_channel(channel_pid) end)

    assert {:ok, _connection} =
             RemoteExec.register_connection(channel_pid, %{
               "workspace_id" => "workspace-boundary-reopen",
               "user_id" => "user-boundary-reopen",
               "participant_id" => "worker-boundary-reopen",
               "participant_role" => "worker"
             })

    assert {:ok, _target} =
             RemoteExec.upsert_target(channel_pid, %{
               "workspace_id" => "workspace-boundary-reopen",
               "user_id" => "user-boundary-reopen",
               "participant_id" => "worker-boundary-reopen",
               "participant_role" => "worker",
               "target_id" => "target-boundary-reopen",
               "capability_id" => "codex.exec.session",
               "runtime_driver" => "asm",
               "provider" => "codex",
               "workspace_root" => "/srv/hive",
               "boundary_reopen_request" => %{
                 "boundary_session_id" => "bnd-target-boundary-reopen",
                 "backend_kind" => "microvm",
                 "boundary_class" => "leased_cell",
                 "attach" => %{"mode" => "attachable", "working_directory" => "/srv/hive"},
                 "refs" => %{
                   "target_id" => "target-boundary-reopen",
                   "runtime_ref" => "runtime-target-boundary-reopen",
                   "correlation_id" => "corr-target-boundary-reopen",
                   "request_id" => "req-target-boundary-reopen"
                 }
               }
             })

    assert {:ok, %TargetDescriptor{} = descriptor} = V2.fetch_target("target-boundary-reopen")

    assert TargetDescriptor.authored_boundary_capability(descriptor) ==
             BoundaryCapability.new!(%{
               supported: true,
               boundary_classes: ["leased_cell"],
               attach_modes: ["guest_bridge"],
               checkpointing: false
             })
  end

  defp target_ids_for(capability_id) do
    assert {:ok, matches} = V2.compatible_targets_for(capability_id, %{})
    Enum.map(matches, & &1.target.target_id)
  end
end
