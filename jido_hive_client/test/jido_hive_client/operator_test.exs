defmodule JidoHiveClient.OperatorTest do
  use ExUnit.Case, async: false

  import Bitwise

  alias JidoHiveClient.{Operator, TestHTTPServer}

  setup do
    config_dir =
      Path.join(
        System.tmp_dir!(),
        "jido_hive_client_operator_#{System.unique_integer([:positive])}"
      )

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

  test "saved rooms are namespaced by api base url" do
    local_api_base_url = "http://127.0.0.1:4000/api"
    prod_api_base_url = "https://example.com/api"

    assert Operator.list_saved_rooms(local_api_base_url) == []
    assert Operator.list_saved_rooms(prod_api_base_url) == []

    assert :ok = Operator.add_saved_room("room-local-a", local_api_base_url)
    assert :ok = Operator.add_saved_room("room-prod-a", prod_api_base_url)
    assert :ok = Operator.add_saved_room("room-local-b", local_api_base_url)

    assert Operator.list_saved_rooms(local_api_base_url) == ["room-local-a", "room-local-b"]
    assert Operator.list_saved_rooms(prod_api_base_url) == ["room-prod-a"]

    assert :ok = Operator.remove_saved_room("room-local-a", local_api_base_url)
    assert Operator.list_saved_rooms(local_api_base_url) == ["room-local-b"]
  end

  test "store_auth_credential writes credentials with mode 0600" do
    assert :ok =
             Operator.store_auth_credential("github", %{
               connection_id: "conn-abc",
               token: "secret",
               expires_at: "2099-01-01T00:00:00Z"
             })

    stat = File.stat!(Operator.credentials_path())
    assert band(stat.mode, 0o777) == 0o600
  end

  test "load_auth_state prefers the newest connected remote connection" do
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

    auth_state = Operator.load_auth_state(TestHTTPServer.base_url(server), "alice")

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
  end

  test "fetch_room_timeline returns entries and next cursor" do
    {:ok, server} =
      TestHTTPServer.start_link(fn request ->
        assert request.path == "/rooms/room-1/events?after=1"

        {200, %{},
         Jason.encode!(%{
           "data" => [
             %{
               "id" => "evt-2",
               "room_id" => "room-1",
               "sequence" => 2,
               "type" => "room_status_changed",
               "data" => %{"status" => "running"},
               "inserted_at" => "2026-04-11T00:02:00Z"
             }
           ],
           "meta" => %{"next_after_sequence" => 2, "has_more" => false}
         })}
      end)

    on_exit(fn -> TestHTTPServer.stop(server) end)

    assert {:ok,
            %{
              entries: [
                %{
                  "event_id" => "evt-2",
                  "cursor" => "2",
                  "kind" => "room.status_changed",
                  "body" => "running"
                }
              ],
              next_cursor: "2"
            }} =
             Operator.fetch_room_timeline(TestHTTPServer.base_url(server), "room-1", after: 1)
  end

  test "fetch_room returns the decoded room snapshot" do
    {:ok, server} =
      TestHTTPServer.start_link(fn request ->
        case request.path do
          "/rooms/room-1" ->
            {200, %{}, Jason.encode!(%{"data" => canonical_room_resource()})}

          "/rooms/room-1/assignments" ->
            {200, %{}, Jason.encode!(%{"data" => canonical_assignments()})}

          "/rooms/room-1/contributions?limit=200&after_sequence=0" ->
            {200, %{},
             Jason.encode!(%{
               "data" => canonical_contribution_entries(),
               "meta" => %{"next_after_sequence" => 3, "has_more" => false}
             })}
        end
      end)

    on_exit(fn -> TestHTTPServer.stop(server) end)

    assert {:ok,
            %{
              "room_id" => "room-1",
              "status" => "running",
              "brief" => "Discuss architecture",
              "assignments" => [%{"assignment_id" => "asg-1", "objective" => "Draft plan"}],
              "contributions" => [%{"contribution_id" => "ctr-1", "summary" => "Draft plan"}],
              "context_objects" => [%{"context_id" => "ctx-1", "object_type" => "note"}]
            }} =
             Operator.fetch_room(TestHTTPServer.base_url(server), "room-1")
  end

  test "fetch_room_sync returns the consolidated room sync payload" do
    {:ok, server} =
      TestHTTPServer.start_link(fn request ->
        case request.path do
          "/rooms/room-1" ->
            {200, %{}, Jason.encode!(%{"data" => canonical_room_resource()})}

          "/rooms/room-1/assignments" ->
            {200, %{}, Jason.encode!(%{"data" => canonical_assignments()})}

          "/rooms/room-1/contributions?limit=200&after_sequence=0" ->
            {200, %{},
             Jason.encode!(%{
               "data" => canonical_contribution_entries(),
               "meta" => %{"next_after_sequence" => 3, "has_more" => false}
             })}

          "/rooms/room-1/events?after=2" ->
            {200, %{},
             Jason.encode!(%{
               "data" => [
                 %{
                   "id" => "evt-3",
                   "room_id" => "room-1",
                   "sequence" => 3,
                   "type" => "contribution_submitted",
                   "data" => %{
                     "contribution" => %{
                       "id" => "ctr-1",
                       "assignment_id" => "asg-1",
                       "participant_id" => "worker-1",
                       "kind" => "reasoning",
                       "payload" => %{"summary" => "Draft plan"}
                     }
                   },
                   "inserted_at" => "2026-04-11T00:03:00Z"
                 }
               ],
               "meta" => %{"next_after_sequence" => 3, "has_more" => false}
             })}
        end
      end)

    on_exit(fn -> TestHTTPServer.stop(server) end)

    assert {:ok,
            %{
              room_snapshot: %{
                "room_id" => "room-1",
                "status" => "running",
                "workflow_summary" => %{
                  "objective" => "Discuss architecture"
                }
              },
              entries: [
                %{
                  "event_id" => "evt-3",
                  "kind" => "contribution.recorded",
                  "body" => "Draft plan"
                }
              ],
              next_cursor: "3",
              context_objects: [%{"context_id" => "ctx-1"}],
              operations: []
            }} =
             Operator.fetch_room_sync(TestHTTPServer.base_url(server), "room-1", after: 2)
  end

  test "fetch_publication_plan and publish_room go through the shared operator API" do
    parent = self()

    {:ok, server} =
      TestHTTPServer.start_link(fn request ->
        case {request.method, request.path} do
          {"GET", "/rooms/room-1/publication_plan"} ->
            {200, %{},
             Jason.encode!(%{
               "data" => %{
                 "publications" => [
                   %{"channel" => "github", "required_bindings" => [%{"field" => "repo"}]}
                 ]
               }
             })}

          {"POST", "/rooms/room-1/publications"} ->
            send(parent, {:publish_request, Jason.decode!(request.body)})
            {200, %{}, Jason.encode!(%{"data" => %{"status" => "submitted"}})}
        end
      end)

    on_exit(fn -> TestHTTPServer.stop(server) end)

    assert {:ok, %{"publications" => [%{"channel" => "github"}]}} =
             Operator.fetch_publication_plan(TestHTTPServer.base_url(server), "room-1")

    payload = %{"publications" => [%{"channel" => "github", "connection_id" => "conn-1"}]}

    assert {:ok, %{"status" => "submitted"}} =
             Operator.publish_room(TestHTTPServer.base_url(server), "room-1", payload)

    assert_receive {:publish_request, ^payload}
  end

  test "create_room, run operation start/status, and list targets and policies go through the shared operator API" do
    parent = self()

    {:ok, server} =
      TestHTTPServer.start_link(fn request ->
        case {request.method, request.path} do
          {"POST", "/rooms"} ->
            send(parent, {:create_room_request, Jason.decode!(request.body)})

            {201, %{},
             Jason.encode!(%{
               "data" => %{
                 "room" => %{
                   "id" => "room-1",
                   "name" => "Discuss architecture",
                   "status" => "idle",
                   "phase" => "draft",
                   "config" => %{}
                 },
                 "participants" => [],
                 "assignment_counts" => %{
                   "pending" => 0,
                   "active" => 0,
                   "completed" => 0,
                   "expired" => 0
                 },
                 "contribution_count" => 0
               }
             })}

          {"POST", "/rooms/room-1/runs"} ->
            send(parent, {:run_room_request, Jason.decode!(request.body)})

            {202, %{},
             Jason.encode!(%{
               "data" => %{
                 "run" => %{
                   "run_id" => "room_run-op-1",
                   "room_id" => "room-1",
                   "status" => "queued",
                   "max_assignments" => 1,
                   "assignments_started" => 0,
                   "assignments_completed" => 0,
                   "assignment_timeout_ms" => 45_000,
                   "until" => %{"kind" => "policy_complete"},
                   "inserted_at" => "2026-04-11T00:05:00Z",
                   "updated_at" => "2026-04-11T00:05:00Z"
                 }
               }
             })}

          {"GET", "/rooms/room-1/runs/room_run-op-1"} ->
            {200, %{},
             Jason.encode!(%{
               "data" => %{
                 "run" => %{
                   "run_id" => "room_run-op-1",
                   "room_id" => "room-1",
                   "status" => "completed",
                   "max_assignments" => 1,
                   "assignments_started" => 1,
                   "assignments_completed" => 1,
                   "assignment_timeout_ms" => 45_000,
                   "until" => %{"kind" => "policy_complete"},
                   "result" => %{"reason" => "policy_complete"},
                   "inserted_at" => "2026-04-11T00:05:00Z",
                   "updated_at" => "2026-04-11T00:05:05Z"
                 }
               }
             })}

          {"GET", "/targets"} ->
            {200, %{}, Jason.encode!(%{"data" => [%{"target_id" => "worker-01"}]})}

          {"GET", "/policies"} ->
            {200, %{}, Jason.encode!(%{"data" => [%{"policy_id" => "round_robin/v2"}]})}
        end
      end)

    on_exit(fn -> TestHTTPServer.stop(server) end)

    room_payload = %{"room_id" => "room-1", "brief" => "Discuss architecture"}

    assert {:ok,
            %{
              "room_id" => "room-1",
              "status" => "idle",
              "brief" => "Discuss architecture"
            }} =
             Operator.create_room(TestHTTPServer.base_url(server), room_payload)

    assert_receive {:create_room_request,
                    %{
                      "data" => %{
                        "id" => "room-1",
                        "name" => "Discuss architecture",
                        "config" => %{},
                        "participants" => []
                      }
                    }}

    assert {:ok,
            %{
              "operation_id" => "room_run-op-1",
              "client_operation_id" => "room_run-client-op",
              "status" => "queued"
            }} =
             Operator.start_room_run_operation(TestHTTPServer.base_url(server), "room-1",
               max_assignments: 1,
               assignment_timeout_ms: 45_000,
               request_timeout_ms: 55_000,
               client_operation_id: "room_run-client-op",
               operation_id: "room_run-client-op"
             )

    assert_receive {:run_room_request,
                    %{
                      "data" => %{
                        "max_assignments" => 1,
                        "assignment_timeout_ms" => 45_000,
                        "client_operation_id" => "room_run-client-op",
                        "until" => %{"kind" => "policy_complete"}
                      }
                    }}

    assert {:ok,
            %{
              "operation_id" => "room_run-op-1",
              "status" => "completed",
              "result" => %{"reason" => "policy_complete"}
            }} =
             Operator.fetch_room_run_operation(
               TestHTTPServer.base_url(server),
               "room-1",
               "room_run-op-1"
             )

    assert {:ok, [%{"target_id" => "worker-01"}]} =
             Operator.list_targets(TestHTTPServer.base_url(server))

    assert {:ok, [%{"policy_id" => "round_robin/v2"}]} =
             Operator.list_policies(TestHTTPServer.base_url(server))
  end

  test "start_room_run_operation returns structured timeout metadata when the request times out" do
    {:ok, server} =
      TestHTTPServer.start_link(fn request ->
        assert request.path == "/rooms/room-timeout/runs"
        Process.sleep(75)
        {202, %{}, Jason.encode!(%{"data" => %{"run" => %{"run_id" => "room_run-op-timeout"}}})}
      end)

    on_exit(fn -> TestHTTPServer.stop(server) end)

    assert {:error,
            {:timeout,
             %{
               method: "POST",
               path: "/rooms/room-timeout/runs",
               request_timeout_ms: 10,
               operation_id: "room_run-test"
             } = metadata}} =
             Operator.start_room_run_operation(TestHTTPServer.base_url(server), "room-timeout",
               request_timeout_ms: 10,
               assignment_timeout_ms: 5,
               operation_id: "room_run-test"
             )

    assert metadata.elapsed_ms >= 0
  end

  test "start_install and complete_install go through the shared operator API" do
    parent = self()

    {:ok, server} =
      TestHTTPServer.start_link(fn request ->
        case {request.method, request.path} do
          {"POST", "/connectors/github/installs"} ->
            send(parent, {:start_install_request, Jason.decode!(request.body)})
            {200, %{}, Jason.encode!(%{"data" => %{"install_id" => "install-1"}})}

          {"POST", "/connectors/installs/install-1/complete"} ->
            send(parent, {:complete_install_request, Jason.decode!(request.body)})
            {200, %{}, Jason.encode!(%{"data" => %{"connection_id" => "connection-1"}})}
        end
      end)

    on_exit(fn -> TestHTTPServer.stop(server) end)

    assert {:ok, %{"install_id" => "install-1"}} =
             Operator.start_install(TestHTTPServer.base_url(server), "github", "alice", ["repo"])

    assert_receive {:start_install_request,
                    %{
                      "subject" => "alice",
                      "tenant_id" => "workspace-local",
                      "scopes" => ["repo"]
                    }}

    assert {:ok, %{"connection_id" => "connection-1"}} =
             Operator.complete_install(
               TestHTTPServer.base_url(server),
               "install-1",
               "alice",
               "token-123"
             )

    assert_receive {:complete_install_request,
                    %{"subject" => "alice", "access_token" => "token-123"}}
  end

  defp canonical_room_resource do
    %{
      "room" => %{
        "id" => "room-1",
        "name" => "Discuss architecture",
        "status" => "running",
        "phase" => "analysis",
        "config" => %{"dispatch_policy" => "round_robin/v2"},
        "inserted_at" => "2026-04-11T00:00:00Z",
        "updated_at" => "2026-04-11T00:01:00Z"
      },
      "participants" => [
        %{
          "id" => "operator-1",
          "room_id" => "room-1",
          "kind" => "human",
          "handle" => "operator",
          "meta" => %{
            "role" => "facilitator",
            "authority_level" => "binding"
          },
          "joined_at" => "2026-04-11T00:00:01Z"
        }
      ],
      "assignment_counts" => %{
        "pending" => 0,
        "active" => 1,
        "completed" => 1,
        "expired" => 0
      },
      "contribution_count" => 1
    }
  end

  defp canonical_assignments do
    [
      %{
        "id" => "asg-1",
        "room_id" => "room-1",
        "participant_id" => "worker-1",
        "status" => "active",
        "deadline" => "2026-04-11T00:10:00Z",
        "payload" => %{
          "objective" => "Draft plan",
          "phase" => "analysis",
          "context" => %{"brief" => "Discuss architecture", "context_objects" => []},
          "output_contract" => %{"type" => "markdown"},
          "executor" => %{"target_id" => "worker-1"}
        },
        "meta" => %{
          "participant_meta" => %{
            "role" => "analyst",
            "target_id" => "worker-1"
          }
        },
        "inserted_at" => "2026-04-11T00:01:30Z"
      }
    ]
  end

  defp canonical_contribution_entries do
    [
      %{
        "event_sequence" => 3,
        "contribution" => %{
          "id" => "ctr-1",
          "room_id" => "room-1",
          "assignment_id" => "asg-1",
          "participant_id" => "worker-1",
          "kind" => "reasoning",
          "payload" => %{
            "summary" => "Draft plan",
            "context_objects" => [
              %{
                "context_id" => "ctx-1",
                "object_type" => "note",
                "title" => "Plan",
                "body" => "Draft the rollout."
              }
            ]
          },
          "meta" => %{
            "participant_role" => "analyst",
            "participant_kind" => "runtime",
            "target_id" => "worker-1",
            "authority_level" => "advisory",
            "status" => "completed"
          },
          "inserted_at" => "2026-04-11T00:02:00Z"
        }
      }
    ]
  end
end
