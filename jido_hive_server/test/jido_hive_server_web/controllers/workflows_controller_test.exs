defmodule JidoHiveServerWeb.WorkflowsControllerTest do
  use JidoHiveServerWeb.ConnCase, async: true

  test "lists available workflows", %{conn: conn} do
    conn = get(conn, ~p"/api/workflows")

    assert %{"data" => workflows} = json_response(conn, 200)

    assert Enum.any?(workflows, &(&1["workflow_id"] == "default.round_robin/v1"))
    assert Enum.any?(workflows, &(&1["workflow_id"] == "chain_of_responsibility/v1"))
  end

  test "shows one workflow definition", %{conn: conn} do
    conn = get(conn, ~p"/api/workflows/default.round_robin/v1")

    assert %{
             "data" => %{
               "workflow_id" => "default.round_robin/v1",
               "phases" => [%{"phase" => "proposal"} | _]
             }
           } = json_response(conn, 200)
  end
end
