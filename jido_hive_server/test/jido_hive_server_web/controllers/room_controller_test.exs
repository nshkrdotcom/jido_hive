defmodule JidoHiveServerWeb.RoomControllerTest do
  use JidoHiveServerWeb.ConnCase, async: false

  alias Jido.Integration.V2
  alias JidoHiveClient.Executor.Session
  alias JidoHiveClient.RelayWorker
  alias JidoHiveClient.TestSupport.ScriptedRunModule
  alias JidoHiveServer.RemoteExec

  test "creates a room and runs a one-assignment round robin flow", %{conn: conn} do
    port =
      Application.fetch_env!(:jido_hive_server, JidoHiveServerWeb.Endpoint)
      |> Keyword.fetch!(:http)
      |> Keyword.fetch!(:port)

    url = "ws://127.0.0.1:#{port}/socket/websocket"

    start_supervised!(
      {RelayWorker,
       name: :analyst_http_client,
       url: url,
       relay_topic: "relay:local",
       workspace_id: "workspace-http",
       user_id: "user-analyst",
       participant_id: "analyst",
       participant_role: "worker",
       target_id: "target-analyst-http",
       capability_id: "codex.exec.session",
       executor: {Session, [provider: :claude, driver: ScriptedRunModule]}}
    )

    assert wait_until(fn ->
             case V2.compatible_targets_for("codex.exec.session", %{}) do
               {:ok, matches} ->
                 length(RemoteExec.list_targets()) == 1 and
                   length(matches) == 1 and
                   Enum.any?(matches, &(&1.target.target_id == "target-analyst-http"))

               _ ->
                 false
             end
           end)

    create_payload = %{
      "room_id" => "room-http-1",
      "brief" => "Design a distributed participation substrate.",
      "rules" => ["Return structured contributions only."],
      "dispatch_policy_id" => "round_robin/v2",
      "dispatch_policy_config" => %{
        "phases" => [
          %{
            "phase" => "analysis",
            "objective" => "Analyze the brief.",
            "allowed_contribution_types" => ["reasoning"],
            "allowed_object_types" => ["belief", "note"],
            "allowed_relation_types" => ["derives_from", "references"]
          }
        ]
      },
      "participants" => [
        %{
          "participant_id" => "analyst",
          "participant_role" => "worker",
          "participant_kind" => "runtime",
          "target_id" => "target-analyst-http",
          "capability_id" => "codex.exec.session"
        }
      ]
    }

    create_conn = post(conn, ~p"/api/rooms", create_payload)

    assert %{
             "data" => %{
               "room_id" => "room-http-1",
               "status" => "idle",
               "dispatch_policy_id" => "round_robin/v2"
             }
           } = json_response(create_conn, 201)

    run_conn =
      post(recycle(create_conn), ~p"/api/rooms/room-http-1/run", %{
        "max_assignments" => 1,
        "assignment_timeout_ms" => 5_000
      })

    assert %{
             "data" => %{
               "room_id" => "room-http-1",
               "status" => "publication_ready",
               "context_objects" => [_ | _],
               "contributions" => [%{"summary" => _summary}],
               "assignments" => [%{"status" => "completed"}]
             }
           } = json_response(run_conn, 200)
  end

  defp wait_until(fun, attempts \\ 100)

  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(50)
      wait_until(fun, attempts - 1)
    end
  end
end
