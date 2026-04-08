defmodule JidoHiveTermuiConsole.AuthTest do
  use ExUnit.Case, async: false

  import Bitwise

  alias JidoHiveTermuiConsole.{Auth, Config, TestSupport}

  setup do
    config_dir = TestSupport.tmp_dir()
    previous = Application.get_env(:jido_hive_termui_console, :config_dir)
    Application.put_env(:jido_hive_termui_console, :config_dir, config_dir)

    on_exit(fn ->
      if previous do
        Application.put_env(:jido_hive_termui_console, :config_dir, previous)
      else
        Application.delete_env(:jido_hive_termui_console, :config_dir)
      end

      File.rm_rf!(config_dir)
    end)

    :ok = Config.ensure_initialized()
    %{config_dir: config_dir}
  end

  test "load_all reports cached and missing providers" do
    File.write!(
      Config.credentials_path(),
      Jason.encode!(%{
        "github" => %{
          "connection_id" => "conn-123",
          "token" => "ghp",
          "expires_at" => "2099-01-01T00:00:00Z"
        }
      })
    )

    assert Auth.load_all() == %{"github" => :cached, "notion" => :missing}
    assert Auth.connection_id("github") == "conn-123"
  end

  test "store writes credentials with mode 0600" do
    assert :ok =
             Auth.store("github", %{
               connection_id: "conn-abc",
               token: "secret",
               expires_at: "2099-01-01T00:00:00Z"
             })

    stat = File.stat!(Config.credentials_path())
    assert band(stat.mode, 0o777) == 0o600
  end

  test "load_all treats unknown or expired entries as missing" do
    File.write!(
      Config.credentials_path(),
      Jason.encode!(%{
        "github" => %{"connection_id" => "conn-old", "expires_at" => "2000-01-01T00:00:00Z"}
      })
    )

    assert Auth.load_all() == %{"github" => :missing, "notion" => :missing}
  end
end
