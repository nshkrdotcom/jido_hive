defmodule JidoHiveServerWeb.PoliciesControllerTest do
  use JidoHiveServerWeb.ConnCase, async: true

  test "lists available policies", %{conn: conn} do
    conn = get(conn, ~p"/api/policies")

    assert %{"data" => policies} = json_response(conn, 200)

    assert Enum.any?(policies, &(&1["policy_id"] == "round_robin/v2"))
    assert Enum.any?(policies, &(&1["policy_id"] == "resource_pool/v1"))
    assert Enum.any?(policies, &(&1["policy_id"] == "human_gate/v1"))
  end

  test "shows one policy definition", %{conn: conn} do
    conn = get(conn, ~p"/api/policies/round_robin/v2")

    assert %{
             "data" => %{
               "policy_id" => "round_robin/v2",
               "display_name" => "Round Robin"
             }
           } = json_response(conn, 200)
  end
end
