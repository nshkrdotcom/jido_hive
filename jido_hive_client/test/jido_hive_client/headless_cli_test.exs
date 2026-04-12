defmodule JidoHiveClient.HeadlessCLITest do
  use ExUnit.Case, async: false

  alias JidoHiveClient.HeadlessCLI

  defmodule OperatorStub do
    def load_config do
      %{
        "api_base_url" => "http://127.0.0.1:4000/api",
        "participant_role" => "coordinator",
        "poll_interval_ms" => 250
      }
    end

    def list_saved_rooms("https://example.com/api"), do: ["room-a", "room-b"]

    def fetch_room("https://example.com/api", "room-1") do
      {:ok,
       %{
         "id" => "room-1",
         "name" => "Stabilize the Redis auth path",
         "status" => "running",
         "workflow_summary" => %{
           "objective" => "Stabilize the Redis auth path",
           "stage" => "Resolve contradictions",
           "next_action" => "Review ctx-4 and submit a binding resolution",
           "blockers" => [%{"kind" => "contradiction", "count" => 2}],
           "publish_ready" => false,
           "publish_blockers" => ["Open contradictions remain"],
           "graph_counts" => %{
             "duplicates" => 1,
             "contradictions" => 1,
             "decisions" => 1,
             "stale" => 0,
             "total" => 3
           },
           "focus_candidates" => [
             %{"kind" => "contradiction", "context_id" => "ctx-4"},
             %{"kind" => "duplicate_cluster", "context_id" => "ctx-1", "duplicate_count" => 1}
           ]
         },
         "context_objects" => [
           %{
             "context_id" => "ctx-1",
             "object_type" => "belief",
             "title" => "Redis timeout",
             "derived" => %{
               "duplicate_status" => "canonical",
               "duplicate_size" => 2,
               "duplicate_context_ids" => ["ctx-1", "ctx-2"],
               "canonical_context_id" => "ctx-1"
             },
             "relations" => [%{"relation" => "derives_from", "target_id" => "ctx-9"}]
           },
           %{
             "context_id" => "ctx-4",
             "object_type" => "contradiction",
             "title" => "Redis is healthy",
             "relations" => [%{"relation" => "references", "target_id" => "ctx-1"}]
           },
           %{
             "context_id" => "ctx-9",
             "object_type" => "evidence",
             "title" => "Grafana latency chart",
             "relations" => []
           }
         ],
         "operations" => [%{"operation_id" => "room_run-1", "status" => "running"}]
       }}
    end

    def list_room_events("https://example.com/api", "room-1", opts) when is_list(opts) do
      after_cursor = Keyword.get(opts, :after)
      send(test_pid(), {:list_room_events, after_cursor})

      case after_cursor do
        "evt-1" ->
          {:ok, %{entries: [%{"event_id" => "evt-2"}], next_cursor: "evt-2"}}

        _other ->
          {:ok, %{entries: [%{"event_id" => "evt-3"}], next_cursor: "evt-3"}}
      end
    end

    def create_room("https://example.com/api", payload) do
      send(test_pid(), {:create_room, payload})
      {:ok, %{"id" => payload["id"], "name" => payload["name"], "status" => "idle"}}
    end

    def start_room_run_operation("https://example.com/api", "room-1", opts) do
      send(test_pid(), {:run_room, opts})
      {:ok, %{"operation_id" => "room_run-op-1", "status" => "accepted"}}
    end

    def fetch_room_run_operation("https://example.com/api", "room-1", "room_run-op-1") do
      {:ok, %{"operation_id" => "room_run-op-1", "status" => "completed"}}
    end

    def add_saved_room(room_id, api_base_url) do
      send(test_pid(), {:add_saved_room, room_id, api_base_url})
      :ok
    end

    def load_auth_state("https://example.com/api", "alice") do
      %{"github" => %{status: :cached, connection_id: "conn-1"}}
    end

    def submit_contribution("https://example.com/api", "room-1", payload) do
      send(test_pid(), {:submit_contribution, payload})
      {:ok, %{"status" => "completed"}}
    end

    defp test_pid do
      Application.fetch_env!(:jido_hive_client, :headless_cli_test_pid)
    end
  end

  defmodule EmbeddedStub do
    def start_link(opts) do
      send(test_pid(), {:start_link, opts})
      Agent.start_link(fn -> %{opts: opts} end)
    end

    def snapshot(_session), do: %{"room_id" => "room-1", "timeline" => []}

    def refresh(_session),
      do: {:ok, %{"room_id" => "room-1", "timeline" => [%{"event_id" => "evt-1"}]}}

    def submit_chat(_session, attrs) do
      send(test_pid(), {:submit_chat, attrs})
      {:ok, %{"summary" => Map.get(attrs, :text)}}
    end

    def accept_context(_session, context_id, attrs) do
      send(test_pid(), {:accept_context, context_id, attrs})
      {:ok, %{"accepted_context_id" => context_id}}
    end

    def shutdown(session) do
      send(test_pid(), {:shutdown, session})
      GenServer.stop(session)
      :ok
    end

    defp test_pid do
      Application.fetch_env!(:jido_hive_client, :headless_cli_test_pid)
    end
  end

  setup do
    Application.put_env(:jido_hive_client, :headless_cli_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:jido_hive_client, :headless_cli_test_pid)
    end)

    :ok
  end

  test "operator rooms list returns namespaced saved rooms" do
    assert {:ok, %{"api_base_url" => "https://example.com/api", "rooms" => ["room-a", "room-b"]}} =
             HeadlessCLI.dispatch(
               ["room", "list", "--api-base-url", "https://example.com/api"],
               operator_module: OperatorStub
             )
  end

  test "operator room get and timeline use the shared operator API" do
    assert {:ok, %{"id" => "room-1", "status" => "running"}} =
             HeadlessCLI.dispatch(
               [
                 "operator",
                 "room",
                 "get",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1"
               ],
               operator_module: OperatorStub
             )

    assert {:ok, %{"entries" => [%{"event_id" => "evt-2"}], "next_cursor" => "evt-2"}} =
             HeadlessCLI.dispatch(
               [
                 "operator",
                 "room",
                 "timeline",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1",
                 "--after",
                 "evt-1"
               ],
               operator_module: OperatorStub
             )
  end

  test "operator room workflow returns the canonical workflow summary from room detail and events" do
    assert {:ok,
            %{
              "room_id" => "room-1",
              "status" => "running",
              "workflow_summary" => %{
                "objective" => "Stabilize the Redis auth path",
                "stage" => "Resolve contradictions",
                "graph_counts" => %{"duplicates" => 1}
              }
            }} =
             HeadlessCLI.dispatch(
               [
                 "room",
                 "workflow",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1"
               ],
               operator_module: OperatorStub
             )

    assert_receive {:list_room_events, nil}
  end

  test "operator room workspace returns structured room workspace data" do
    assert {:ok,
            %{
              "room_id" => "room-1",
              "graph_sections" => [%{"title" => "CONFLICTS"} | _],
              "selected_detail" => %{"context_id" => "ctx-4"}
            }} =
             HeadlessCLI.dispatch(
               [
                 "room",
                 "workspace",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1",
                 "--selected-context-id",
                 "ctx-4"
               ],
               operator_module: OperatorStub
             )
  end

  test "operator room inspect returns the consolidated sync surface plus workflow summary" do
    assert {:ok,
            %{
              "room_id" => "room-1",
              "status" => "running",
              "control_plane" => %{
                "reason" => "Open contradictions remain"
              },
              "workflow_summary" => %{
                "stage" => "Resolve contradictions"
              },
              "entries" => [%{"event_id" => "evt-3"}],
              "context_objects" => [%{"context_id" => "ctx-1"} | _rest],
              "operations" => [%{"operation_id" => "room_run-1", "status" => "running"}],
              "next_cursor" => "evt-3"
            }} =
             HeadlessCLI.dispatch(
               [
                 "room",
                 "inspect",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1",
                 "--after",
                 "evt-2"
               ],
               operator_module: OperatorStub
             )

    assert_receive {:list_room_events, "evt-2"}
  end

  test "operator room focus returns the shared control-plane digest" do
    assert {:ok,
            %{
              "room_id" => "room-1",
              "status" => "running",
              "control_plane" => %{
                "stage" => "Resolve contradictions",
                "reason" => "Open contradictions remain",
                "focus_queue" => [
                  %{
                    "kind" => "contradiction",
                    "context_id" => "ctx-4",
                    "action" => "Open conflict resolution"
                  },
                  %{
                    "kind" => "duplicate_cluster",
                    "context_id" => "ctx-1",
                    "action" => "Review the canonical entry before accepting or publishing"
                  }
                ]
              }
            }} =
             HeadlessCLI.dispatch(
               [
                 "room",
                 "focus",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1"
               ],
               operator_module: OperatorStub
             )

    assert_receive {:list_room_events, nil}
  end

  test "operator room provenance returns the shared provenance trace for a context object" do
    assert {:ok,
            %{
              "room_id" => "room-1",
              "status" => "running",
              "provenance" => %{
                "context_id" => "ctx-4",
                "title" => "Redis is healthy",
                "recommended_actions" => [
                  %{"label" => "Open conflict resolution", "shortcut" => "Enter"},
                  %{"label" => "Inspect provenance", "shortcut" => "Ctrl+E"},
                  %{"label" => "Accept selected object", "shortcut" => "Ctrl+A"}
                ],
                "trace" => [
                  %{"context_id" => "ctx-4", "depth" => 0, "via" => nil},
                  %{"context_id" => "ctx-1", "depth" => 1, "via" => "references"},
                  %{"context_id" => "ctx-9", "depth" => 2, "via" => "derives_from"}
                ]
              }
            }} =
             HeadlessCLI.dispatch(
               [
                 "room",
                 "provenance",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1",
                 "--context-id",
                 "ctx-4"
               ],
               operator_module: OperatorStub
             )

    assert_receive {:list_room_events, nil}
  end

  test "publication commands are no longer part of the core headless CLI" do
    assert {:error, :unsupported_command} =
             HeadlessCLI.dispatch(
               [
                 "room",
                 "publish-plan",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1"
               ],
               operator_module: OperatorStub
             )

    assert {:error, :unsupported_command} =
             HeadlessCLI.dispatch(
               [
                 "room",
                 "publication-workspace",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1",
                 "--subject",
                 "alice"
               ],
               operator_module: OperatorStub
             )

    assert {:error, :unsupported_command} =
             HeadlessCLI.dispatch(
               [
                 "room",
                 "publish",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1",
                 "--payload-file",
                 "/tmp/publish.json"
               ],
               operator_module: OperatorStub
             )
  end

  test "operator room create persists the room locally after creation" do
    payload_file =
      Path.join(System.tmp_dir!(), "jido_hive_payload_#{System.unique_integer([:positive])}.json")

    File.write!(
      payload_file,
      Jason.encode!(%{"id" => "room-1", "name" => "Discuss architecture"})
    )

    on_exit(fn -> File.rm(payload_file) end)

    assert {:ok,
            %{
              "operation_id" => operation_id,
              "result" => %{
                "id" => "room-1",
                "name" => "Discuss architecture",
                "status" => "idle"
              }
            }} =
             HeadlessCLI.dispatch(
               [
                 "operator",
                 "room",
                 "create",
                 "--api-base-url",
                 "https://example.com/api",
                 "--payload-file",
                 payload_file
               ],
               operator_module: OperatorStub
             )

    assert String.starts_with?(operation_id, "room_create-")

    assert_receive {:create_room, %{"id" => "room-1", "name" => "Discuss architecture"}}
    assert_receive {:add_saved_room, "room-1", "https://example.com/api"}
  end

  test "operator auth state returns current connector status" do
    assert {:ok, %{"github" => %{"connection_id" => "conn-1", "status" => "cached"}}} =
             HeadlessCLI.dispatch(
               [
                 "operator",
                 "auth",
                 "state",
                 "--api-base-url",
                 "https://example.com/api",
                 "--subject",
                 "alice"
               ],
               operator_module: OperatorStub
             )
  end

  test "operator room run starts an explicit run operation" do
    assert {:ok, %{"operation_id" => "room_run-op-1", "status" => "accepted"}} =
             HeadlessCLI.dispatch(
               [
                 "room",
                 "run",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1",
                 "--max-assignments",
                 "1",
                 "--assignment-timeout-ms",
                 "45000",
                 "--request-timeout-ms",
                 "60000"
               ],
               operator_module: OperatorStub
             )

    assert_receive {:run_room, opts}
    assert Keyword.get(opts, :max_assignments) == 1
    assert Keyword.get(opts, :assignment_timeout_ms) == 45_000
    assert Keyword.get(opts, :request_timeout_ms) == 60_000
  end

  test "operator room run-status fetches the explicit run operation state" do
    assert {:ok, %{"operation_id" => "room_run-op-1", "status" => "completed"}} =
             HeadlessCLI.dispatch(
               [
                 "room",
                 "run-status",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1",
                 "--operation-id",
                 "room_run-op-1"
               ],
               operator_module: OperatorStub
             )
  end

  test "session room submit-chat starts an embedded session and submits the message" do
    assert {:ok, %{"operation_id" => operation_id, "result" => %{"summary" => "hello from cli"}}} =
             HeadlessCLI.dispatch(
               [
                 "session",
                 "room",
                 "submit-chat",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1",
                 "--participant-id",
                 "alice",
                 "--text",
                 "hello from cli",
                 "--selected-context-id",
                 "ctx-1",
                 "--selected-context-object-type",
                 "belief",
                 "--selected-relation",
                 "supports"
               ],
               operator_module: OperatorStub,
               embedded_module: EmbeddedStub
             )

    assert String.starts_with?(operation_id, "room_submit-")

    assert_receive {:start_link, start_opts}
    assert Keyword.fetch!(start_opts, :room_id) == "room-1"
    assert_receive {:submit_chat, attrs}
    assert attrs.text == "hello from cli"
    assert attrs.selected_context_id == "ctx-1"
    assert attrs.selected_relation == "supports"
    refute Map.has_key?(attrs, :authority_level)
    assert_receive {:shutdown, _session}
  end

  test "session room accept-context uses the embedded session" do
    assert {:ok,
            %{"operation_id" => operation_id, "result" => %{"accepted_context_id" => "ctx-1"}}} =
             HeadlessCLI.dispatch(
               [
                 "session",
                 "room",
                 "accept-context",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1",
                 "--participant-id",
                 "alice",
                 "--context-id",
                 "ctx-1"
               ],
               operator_module: OperatorStub,
               embedded_module: EmbeddedStub
             )

    assert String.starts_with?(operation_id, "room_accept-")

    assert_receive {:accept_context, "ctx-1", %{}}
    assert_receive {:shutdown, _session}
  end

  test "room resolve submits a resolver contribution through the shared operator API" do
    assert {:ok, %{"operation_id" => operation_id, "result" => %{"status" => "completed"}}} =
             HeadlessCLI.dispatch(
               [
                 "room",
                 "resolve",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-1",
                 "--participant-id",
                 "alice",
                 "--left",
                 "ctx-1",
                 "--right",
                 "ctx-2",
                 "--text",
                 "Choose ctx-1 and close the contradiction"
               ],
               operator_module: OperatorStub
             )

    assert String.starts_with?(operation_id, "room_resolve-")

    assert_receive {:submit_contribution, payload}
    assert payload["room_id"] == "room-1"
    assert payload["participant_id"] == "alice"
    refute Map.has_key?(payload, "authority_level")

    assert get_in(payload, ["payload", "context_objects"]) == [
             %{
               "object_type" => "decision",
               "title" => "Choose ctx-1 and close the contradiction",
               "body" => "Choose ctx-1 and close the contradiction",
               "relations" => [
                 %{"relation" => "resolves", "target_id" => "ctx-1"},
                 %{"relation" => "resolves", "target_id" => "ctx-2"}
               ]
             }
           ]

    assert get_in(payload, ["meta", "status"]) == "completed"
  end
end
