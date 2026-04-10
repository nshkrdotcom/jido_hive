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
       capability_id: "workspace.exec.session",
       executor: {Session, [provider: :claude, driver: ScriptedRunModule]}}
    )

    assert wait_until(fn ->
             case V2.compatible_targets_for("workspace.exec.session", %{}) do
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
          "capability_id" => "workspace.exec.session"
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
      post(recycle(create_conn), ~p"/api/rooms/room-http-1/run_operations", %{
        "max_assignments" => 1,
        "assignment_timeout_ms" => 5_000,
        "client_operation_id" => "room_run-client-http-1"
      })

    assert %{
             "data" => %{
               "operation_id" => operation_id,
               "client_operation_id" => "room_run-client-http-1",
               "room_id" => "room-http-1",
               "status" => "accepted"
             }
           } = json_response(run_conn, 202)

    assert {:ok, %{"status" => "completed"}} =
             wait_for_run_operation(create_conn, "room-http-1", operation_id)

    room_conn = get(recycle(create_conn), ~p"/api/rooms/room-http-1")

    assert %{
             "data" => %{
               "room_id" => "room-http-1",
               "status" => "publication_ready",
               "context_objects" => [_ | _],
               "contributions" => [%{"summary" => _summary}],
               "assignments" => [%{"status" => "completed"}]
             }
           } = json_response(room_conn, 200)
  end

  test "runs a room created from string phase ids like the console wizard payload", %{conn: conn} do
    port =
      Application.fetch_env!(:jido_hive_server, JidoHiveServerWeb.Endpoint)
      |> Keyword.fetch!(:http)
      |> Keyword.fetch!(:port)

    url = "ws://127.0.0.1:#{port}/socket/websocket"

    start_supervised!(
      {RelayWorker,
       name: :analyst_http_string_phase_client,
       url: url,
       relay_topic: "relay:local",
       workspace_id: "workspace-http",
       user_id: "user-analyst",
       participant_id: "analyst",
       participant_role: "worker",
       target_id: "target-analyst-http",
       capability_id: "workspace.exec.session",
       executor: {Session, [provider: :claude, driver: ScriptedRunModule]}}
    )

    assert wait_until(fn ->
             case V2.compatible_targets_for("workspace.exec.session", %{}) do
               {:ok, matches} ->
                 length(RemoteExec.list_targets()) == 1 and
                   length(matches) == 1 and
                   Enum.any?(matches, &(&1.target.target_id == "target-analyst-http"))

               _ ->
                 false
             end
           end)

    create_payload = %{
      "room_id" => "room-http-string-phases-1",
      "brief" => "Validate string phase ids from the console wizard payload.",
      "rules" => ["Return structured contributions only."],
      "dispatch_policy_id" => "round_robin/v2",
      "dispatch_policy_config" => %{
        "phases" => ["analysis"]
      },
      "participants" => [
        %{
          "participant_id" => "analyst",
          "participant_role" => "worker",
          "participant_kind" => "runtime",
          "target_id" => "target-analyst-http",
          "capability_id" => "workspace.exec.session"
        }
      ]
    }

    create_conn = post(conn, ~p"/api/rooms", create_payload)

    assert %{
             "data" => %{
               "room_id" => "room-http-string-phases-1",
               "status" => "idle",
               "dispatch_policy_id" => "round_robin/v2"
             }
           } = json_response(create_conn, 201)

    run_conn =
      post(recycle(create_conn), ~p"/api/rooms/room-http-string-phases-1/run_operations", %{
        "max_assignments" => 1,
        "assignment_timeout_ms" => 5_000,
        "client_operation_id" => "room_run-client-http-string"
      })

    assert %{
             "data" => %{
               "operation_id" => operation_id,
               "client_operation_id" => "room_run-client-http-string",
               "room_id" => "room-http-string-phases-1",
               "status" => "accepted"
             }
           } = json_response(run_conn, 202)

    assert {:ok, %{"status" => "completed"}} =
             wait_for_run_operation(create_conn, "room-http-string-phases-1", operation_id)

    room_conn = get(recycle(create_conn), ~p"/api/rooms/room-http-string-phases-1")

    assert %{
             "data" => %{
               "room_id" => "room-http-string-phases-1",
               "status" => "publication_ready",
               "context_objects" => [_ | _],
               "contributions" => [%{"summary" => _summary}],
               "assignments" => [%{"status" => "completed"}]
             }
           } = json_response(room_conn, 200)
  end

  test "sync returns the room snapshot, decorated context, timeline delta, and run operations", %{
    conn: conn
  } do
    create_payload = %{
      "room_id" => "room-http-sync-1",
      "brief" => "Exercise the consolidated room sync endpoint.",
      "rules" => ["Return structured contributions only."],
      "dispatch_policy_id" => "round_robin/v2",
      "dispatch_policy_config" => %{"phases" => ["analysis"]},
      "participants" => []
    }

    create_conn = post(conn, ~p"/api/rooms", create_payload)

    assert %{"data" => %{"room_id" => "room-http-sync-1"}} = json_response(create_conn, 201)

    contribution_conn =
      post(recycle(create_conn), ~p"/api/rooms/room-http-sync-1/contributions", %{
        "room_id" => "room-http-sync-1",
        "participant_id" => "alice",
        "participant_role" => "coordinator",
        "participant_kind" => "human",
        "contribution_type" => "chat",
        "authority_level" => "binding",
        "summary" => "Hello sync",
        "context_objects" => [
          %{
            "object_type" => "message",
            "title" => "alice said",
            "body" => "Hello sync"
          }
        ],
        "events" => [
          %{
            "event_type" => "chat.message",
            "body" => "Hello sync"
          }
        ],
        "execution" => %{"status" => "completed"},
        "status" => "completed"
      })

    assert %{"data" => %{"room_id" => "room-http-sync-1"}} = json_response(contribution_conn, 201)

    run_conn =
      post(recycle(create_conn), ~p"/api/rooms/room-http-sync-1/run_operations", %{
        "client_operation_id" => "room_run-client-sync-1",
        "assignment_timeout_ms" => 500
      })

    assert %{
             "data" => %{
               "operation_id" => operation_id,
               "client_operation_id" => "room_run-client-sync-1"
             }
           } = json_response(run_conn, 202)

    sync_conn = get(recycle(create_conn), ~p"/api/rooms/room-http-sync-1/sync")

    assert %{
             "data" => %{
               "room" => %{"room_id" => "room-http-sync-1"} = room,
               "timeline" => timeline,
               "context_objects" => [%{"object_type" => "message", "body" => "Hello sync"}],
               "operations" => operations,
               "next_cursor" => next_cursor
             }
           } = json_response(sync_conn, 200)

    assert room["status"] in ["idle", "running", "awaiting_authority", "publication_ready"]
    assert Enum.any?(timeline, &(&1["kind"] == "contribution.recorded"))
    assert Enum.any?(operations, &(&1["operation_id"] == operation_id))
    assert is_binary(next_cursor)

    sync_after_conn =
      get(recycle(create_conn), ~p"/api/rooms/room-http-sync-1/sync?after=#{next_cursor}")

    assert %{
             "data" => %{
               "room" => %{"room_id" => "room-http-sync-1"},
               "timeline" => [],
               "context_objects" => [%{"object_type" => "message", "body" => "Hello sync"}],
               "operations" => operations_after,
               "next_cursor" => nil
             }
           } = json_response(sync_after_conn, 200)

    assert Enum.any?(operations_after, &(&1["operation_id"] == operation_id))
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

  defp wait_for_run_operation(conn, room_id, operation_id, attempts \\ 100)

  defp wait_for_run_operation(_conn, _room_id, _operation_id, 0), do: {:error, :timeout}

  defp wait_for_run_operation(conn, room_id, operation_id, attempts) do
    operation_conn = get(recycle(conn), ~p"/api/rooms/#{room_id}/run_operations/#{operation_id}")
    %{"data" => operation} = json_response(operation_conn, 200)

    case operation["status"] do
      "completed" ->
        {:ok, operation}

      "failed" ->
        {:error, operation}

      _other ->
        Process.sleep(50)
        wait_for_run_operation(conn, room_id, operation_id, attempts - 1)
    end
  end
end
