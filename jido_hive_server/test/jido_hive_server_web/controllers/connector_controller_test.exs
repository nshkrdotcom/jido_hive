defmodule JidoHiveServerWeb.ConnectorControllerTest do
  use JidoHiveServerWeb.ConnCase, async: false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Connectors.GitHub

  setup do
    :ok = V2.reset!()
    :ok = V2.register_connector(GitHub)
    :ok
  end

  test "start_install accepts string-keyed HTTP params", %{conn: conn} do
    response =
      conn
      |> post(~p"/api/connectors/github/installs", %{
        "tenant_id" => "workspace-local",
        "actor_id" => "operator-1",
        "auth_type" => "oauth2",
        "subject" => "octocat",
        "requested_scopes" => ["repo"]
      })
      |> json_response(200)

    assert %{
             "data" => %{
               "install" => %{
                 "install_id" => install_id,
                 "connector_id" => "github",
                 "actor_id" => "operator-1",
                 "subject" => "octocat",
                 "state" => "installing"
               },
               "connection" => %{
                 "connection_id" => connection_id,
                 "connector_id" => "github",
                 "subject" => "octocat",
                 "state" => "installing"
               },
               "session_state" => %{"install_id" => session_install_id}
             }
           } = response

    assert session_install_id == install_id
    assert is_binary(connection_id)
  end

  test "complete_install accepts string-keyed HTTP params and ISO8601 datetimes", %{conn: conn} do
    install_id =
      conn
      |> post(~p"/api/connectors/github/installs", %{
        "tenant_id" => "workspace-local",
        "actor_id" => "operator-1",
        "auth_type" => "oauth2",
        "subject" => "octocat"
      })
      |> json_response(200)
      |> get_in(["data", "install", "install_id"])

    expires_at =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(3_600, :second)
      |> DateTime.to_iso8601()

    response =
      conn
      |> recycle()
      |> post(~p"/api/connectors/installs/#{install_id}/complete", %{
        "subject" => "octocat",
        "granted_scopes" => ["repo"],
        "secret" => %{"access_token" => "gho_test_token"},
        "expires_at" => expires_at
      })
      |> json_response(200)

    assert %{
             "data" => %{
               "install" => %{"install_id" => ^install_id, "state" => "completed"},
               "connection" => %{
                 "connector_id" => "github",
                 "subject" => "octocat",
                 "state" => "connected"
               },
               "credential_ref" => %{"id" => credential_ref_id}
             }
           } = response

    assert is_binary(credential_ref_id)
  end
end
