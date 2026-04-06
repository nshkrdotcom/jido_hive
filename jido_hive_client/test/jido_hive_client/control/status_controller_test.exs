defmodule JidoHiveClient.Control.StatusControllerTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  alias JidoHiveClient.{Control.Router, Runtime}

  defp runtime_opts do
    [
      workspace_id: "workspace-1",
      user_id: "user-1",
      participant_id: "participant-1",
      participant_role: "analyst",
      target_id: "target-1",
      capability_id: "capability-1",
      workspace_root: "/workspace",
      executor: {JidoHiveClient.Executor.Scripted, [provider: :codex, role: :analyst]},
      runtime_id: :asm
    ]
  end

  setup do
    {:ok, runtime} = start_supervised({Runtime, runtime_opts()})
    [runtime: runtime]
  end

  test "GET /api/runtime returns the canonical runtime snapshot", %{runtime: runtime} do
    :ok = Runtime.update_connection(runtime, :ready, %{"relay_topic" => "relay:workspace-1"})

    conn = call_router(conn(:get, "/api/runtime"), runtime)
    body = Jason.decode!(conn.resp_body)

    assert conn.status == 200
    assert body["client_id"] == "workspace-1:target-1"
    assert body["identity"]["workspace_id"] == "workspace-1"
    assert body["identity"]["target_id"] == "target-1"
    assert body["connection_status"] == "ready"
    assert body["metrics"]["assignments_completed"] == 0
  end

  test "GET /api/runtime/assignments returns recent assignments", %{runtime: runtime} do
    request = %{
      "assignment" => %{
        "assignment_id" => "asn-1",
        "room_id" => "room-1",
        "participant_id" => "participant-1",
        "participant_role" => "analyst",
        "target_id" => "target-1",
        "capability_id" => "capability-1",
        "session" => %{"provider" => "codex"},
        "contribution_contract" => %{"allowed_contribution_types" => ["reasoning"]},
        "context_view" => %{"brief" => "Design a substrate.", "context_objects" => []}
      }
    }

    execute_conn =
      conn(:post, "/api/runtime/assignments/execute", Jason.encode!(request))
      |> put_req_header("content-type", "application/json")
      |> call_router(runtime)

    assert execute_conn.status == 200

    assignments_conn = call_router(conn(:get, "/api/runtime/assignments"), runtime)
    body = Jason.decode!(assignments_conn.resp_body)

    assert assignments_conn.status == 200
    assert [%{"assignment_id" => "asn-1"}] = body["recent_assignments"]
  end

  test "POST /api/runtime/assignments/execute runs a manual assignment through the configured executor",
       %{runtime: runtime} do
    request = %{
      "assignment" => %{
        "assignment_id" => "asn-1",
        "room_id" => "room-1",
        "participant_id" => "participant-1",
        "participant_role" => "analyst",
        "target_id" => "target-1",
        "capability_id" => "capability-1",
        "session" => %{"provider" => "codex"},
        "contribution_contract" => %{"allowed_contribution_types" => ["reasoning"]},
        "context_view" => %{"brief" => "Design a substrate.", "context_objects" => []}
      }
    }

    conn =
      conn(:post, "/api/runtime/assignments/execute", Jason.encode!(request))
      |> put_req_header("content-type", "application/json")
      |> call_router(runtime)

    body = Jason.decode!(conn.resp_body)
    snapshot = Runtime.snapshot(runtime)

    assert conn.status == 200
    assert body["assignment_id"] == "asn-1"
    assert body["status"] == "completed"
    assert snapshot.metrics.assignments_completed == 1
    assert [%{assignment_id: "asn-1"}] = snapshot.recent_assignments
  end

  test "POST /api/runtime/shutdown invokes the configured shutdown callback", %{runtime: runtime} do
    parent = self()

    conn =
      conn(:post, "/api/runtime/shutdown", "")
      |> call_router(runtime,
        shutdown_fun: fn ->
          send(parent, :shutdown_requested)
          :ok
        end
      )

    body = Jason.decode!(conn.resp_body)

    assert conn.status == 202
    assert body["status"] == "accepted"
    assert_receive :shutdown_requested
  end

  test "returns 404 for removed top-level client control routes", %{runtime: runtime} do
    conn =
      conn(:get, "/api/status")
      |> put_req_header("content-type", "application/json")
      |> call_router(runtime)

    assert conn.status == 404
  end

  defp call_router(conn, runtime, extra_opts \\ []) do
    Router.call(conn, Router.init(Keyword.merge([runtime: runtime], extra_opts)))
  end
end
