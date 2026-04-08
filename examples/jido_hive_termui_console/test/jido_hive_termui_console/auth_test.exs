defmodule JidoHiveTermuiConsole.AuthTest do
  use ExUnit.Case, async: false

  import Bitwise

  alias JidoHiveTermuiConsole.{Auth, Config, HTTP, TestHTTPServer, TestSupport}

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

  test "load_all/3 prefers the newest connected server connection" do
    {:ok, server} =
      TestHTTPServer.start_link(fn request ->
        case request.path do
          "/connectors/github/connections?subject=alice" ->
            {200, %{},
             Jason.encode!(%{
               "data" => [
                 %{
                   "connection_id" => "conn-pending",
                   "state" => "installing",
                   "updated_at" => "2026-04-08T21:26:35Z"
                 },
                 %{
                   "connection_id" => "conn-live",
                   "state" => "connected",
                   "updated_at" => "2026-04-08T21:44:31Z"
                 }
               ]
             })}

          "/connectors/notion/connections?subject=alice" ->
            {200, %{}, Jason.encode!(%{"data" => []})}
        end
      end)

    on_exit(fn -> TestHTTPServer.stop(server) end)

    auth_state = Auth.load_all(TestHTTPServer.base_url(server), "alice", HTTP)

    assert auth_state == %{
             "github" => %{
               connection_id: "conn-live",
               source: :server,
               state: "connected",
               status: :cached
             },
             "notion" => %{
               connection_id: nil,
               source: :server,
               state: nil,
               status: :missing
             }
           }

    assert Auth.connection_id(auth_state, "github") == "conn-live"
    assert Auth.connection_id(auth_state, "notion") == nil
  end

  test "load_all/3 falls back to local credentials when server auth fetch fails" do
    File.write!(
      Config.credentials_path(),
      Jason.encode!(%{
        "github" => %{
          "connection_id" => "conn-local",
          "token" => "ghp",
          "expires_at" => "2099-01-01T00:00:00Z"
        }
      })
    )

    {:ok, server} =
      TestHTTPServer.start_link(fn _request ->
        {500, %{}, Jason.encode!(%{"error" => "boom"})}
      end)

    on_exit(fn -> TestHTTPServer.stop(server) end)

    assert Auth.load_all(TestHTTPServer.base_url(server), "alice", HTTP) == %{
             "github" => %{
               connection_id: "conn-local",
               source: :local,
               state: "cached",
               status: :cached
             },
             "notion" => %{
               connection_id: nil,
               source: :missing,
               state: nil,
               status: :missing
             }
           }
  end
end
