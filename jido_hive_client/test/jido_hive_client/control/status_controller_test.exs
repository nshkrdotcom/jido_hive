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
      participant_role: "architect",
      target_id: "target-1",
      capability_id: "capability-1",
      workspace_root: "/workspace",
      executor: {JidoHiveClient.Executor.Scripted, [provider: :codex, role: :architect]},
      runtime_id: :asm
    ]
  end

  setup do
    {:ok, runtime} = start_supervised({Runtime, runtime_opts()})
    [runtime: runtime]
  end

  test "GET /api/status returns summarized runtime status", %{runtime: runtime} do
    :ok = Runtime.update_connection(runtime, :ready, %{"relay_topic" => "relay:workspace-1"})

    conn = call_router(conn(:get, "/api/status"), runtime)
    body = Jason.decode!(conn.resp_body)

    assert conn.status == 200
    assert body["client_id"] == "workspace-1:target-1"
    assert body["connection_status"] == "ready"
    assert body["metrics"]["jobs_completed"] == 0
  end

  test "GET /api/snapshot returns the full runtime snapshot", %{runtime: runtime} do
    conn = call_router(conn(:get, "/api/snapshot"), runtime)
    body = Jason.decode!(conn.resp_body)

    assert conn.status == 200
    assert body["identity"]["workspace_id"] == "workspace-1"
    assert body["identity"]["target_id"] == "target-1"
  end

  test "POST /api/execute runs a manual job through the configured executor", %{runtime: runtime} do
    request = %{
      "job" => %{
        "job_id" => "job-1",
        "room_id" => "room-1",
        "participant_id" => "participant-1",
        "participant_role" => "architect",
        "target_id" => "target-1",
        "capability_id" => "capability-1",
        "session" => %{"provider" => "codex"},
        "collaboration_envelope" => %{"turn" => %{"phase" => "proposal"}}
      }
    }

    conn =
      conn(:post, "/api/execute", Jason.encode!(request))
      |> put_req_header("content-type", "application/json")
      |> call_router(runtime)

    body = Jason.decode!(conn.resp_body)
    snapshot = Runtime.snapshot(runtime)

    assert conn.status == 200
    assert body["job_id"] == "job-1"
    assert body["status"] == "completed"
    assert snapshot.metrics.jobs_completed == 1
    assert [%{job_id: "job-1"}] = snapshot.recent_jobs
  end

  test "POST /api/shutdown invokes the configured shutdown callback", %{runtime: runtime} do
    parent = self()

    conn =
      conn(:post, "/api/shutdown", "")
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

  test "returns 404 for room orchestration endpoints", %{runtime: runtime} do
    conn =
      conn(:post, "/api/rooms", "{}")
      |> put_req_header("content-type", "application/json")
      |> call_router(runtime)

    assert conn.status == 404
  end

  defp call_router(conn, runtime, extra_opts \\ []) do
    Router.call(conn, Router.init(Keyword.merge([runtime: runtime], extra_opts)))
  end
end
