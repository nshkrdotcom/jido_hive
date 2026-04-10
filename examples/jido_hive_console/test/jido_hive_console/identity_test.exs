defmodule JidoHiveConsole.IdentityTest do
  use ExUnit.Case, async: false

  alias JidoHiveClient.Operator
  alias JidoHiveConsole.{Identity, TestSupport}

  setup do
    config_dir = TestSupport.tmp_dir()
    previous = Application.get_env(:jido_hive_client, :config_dir)
    Application.put_env(:jido_hive_client, :config_dir, config_dir)

    on_exit(fn ->
      if previous do
        Application.put_env(:jido_hive_client, :config_dir, previous)
      else
        Application.delete_env(:jido_hive_client, :config_dir)
      end

      File.rm_rf!(config_dir)
    end)

    :ok = Operator.ensure_initialized()
    %{config_dir: config_dir}
  end

  test "load prefers CLI opts over config file" do
    File.write!(
      Path.join(Operator.config_dir(), "config.json"),
      Jason.encode!(%{
        "participant_id" => "config-user",
        "participant_role" => "reviewer",
        "authority_level" => "advisory"
      })
    )

    identity =
      Identity.load(
        participant_id: "cli-user",
        participant_role: "coordinator",
        authority_level: "binding"
      )

    assert identity.participant_id == "cli-user"
    assert identity.participant_role == "coordinator"
    assert identity.authority_level == "binding"
  end

  test "load falls back to generated human identity" do
    identity = Identity.load()
    assert String.starts_with?(identity.participant_id, "human-")
    assert identity.participant_role == "coordinator"
    assert identity.authority_level == "binding"
  end
end
