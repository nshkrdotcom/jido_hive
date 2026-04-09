defmodule JidoHiveServer.RemoteExecTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias Jido.Integration.V2
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
               "capability_id" => "workspace.exec.session",
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
    assert target.capability_id == "workspace.exec.session"
    assert target.provider == "codex"
    assert target.execution_surface["surface_kind"] == "ssh_exec"
    assert target.execution_environment["workspace_root"] == "/tmp/jido_hive_observable"
    assert target.provider_options["model"] == "gpt-5.4"

    assert {:ok, fetched_target} = RemoteExec.fetch_target("target-observable")
    assert fetched_target.participant_id == "architect"
    assert fetched_target.capability_id == "workspace.exec.session"
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
               "capability_id" => "workspace.exec.session",
               "runtime_driver" => "asm",
               "provider" => "codex",
               "workspace_root" => "/tmp/jido_hive_cleanup"
             })

    assert target_ids_for("workspace.exec.session") |> Enum.member?("target-cleanup")

    assert :ok = RemoteExec.remove_channel(channel_pid)
    refute Enum.any?(RemoteExec.list_targets(), &(&1.target_id == "target-cleanup"))
    refute target_ids_for("workspace.exec.session") |> Enum.member?("target-cleanup")
  end

  defp target_ids_for(capability_id) do
    assert {:ok, matches} = V2.compatible_targets_for(capability_id, %{})
    Enum.map(matches, & &1.target.target_id)
  end
end
