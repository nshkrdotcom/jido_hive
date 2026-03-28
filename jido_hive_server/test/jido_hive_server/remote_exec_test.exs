defmodule JidoHiveServer.RemoteExecTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias Jido.Integration.V2
  alias JidoHiveServer.RemoteExec

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

  defp target_ids_for(capability_id) do
    assert {:ok, matches} = V2.compatible_targets_for(capability_id, %{})
    Enum.map(matches, & &1.target.target_id)
  end
end
