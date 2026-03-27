defmodule JidoHiveServerWeb.RoomControllerTest do
  use JidoHiveServerWeb.ConnCase, async: false

  alias Jido.Integration.V2
  alias JidoHiveClient.Executor.Session
  alias JidoHiveClient.RelayWorker
  alias JidoHiveClient.TestSupport.ScriptedRunModule
  alias JidoHiveServer.RemoteExec

  defmodule GatewayStub do
    @behaviour JidoHiveServer.Publications.Gateway

    @impl true
    def invoke_publication(plan, input, _opts) do
      {:ok, %{run: %{run_id: "run-#{plan.channel}"}, output: %{"input" => input}}}
    end
  end

  setup do
    old_gateway = Application.get_env(:jido_hive_server, :publication_gateway)
    Application.put_env(:jido_hive_server, :publication_gateway, GatewayStub)

    on_exit(fn ->
      if old_gateway do
        Application.put_env(:jido_hive_server, :publication_gateway, old_gateway)
      else
        Application.delete_env(:jido_hive_server, :publication_gateway)
      end
    end)

    :ok
  end

  test "creates a room, runs the refereed slice, and executes publication runs", %{conn: conn} do
    port =
      Application.fetch_env!(:jido_hive_server, JidoHiveServerWeb.Endpoint)
      |> Keyword.fetch!(:http)
      |> Keyword.fetch!(:port)

    url = "ws://127.0.0.1:#{port}/socket/websocket"

    start_supervised!(
      {RelayWorker,
       name: :architect_http_client,
       url: url,
       relay_topic: "relay:local",
       workspace_id: "workspace-http",
       user_id: "user-architect",
       participant_id: "architect",
       participant_role: "architect",
       target_id: "target-architect-http",
       capability_id: "codex.exec.session",
       executor: {Session, [provider: :claude, driver: ScriptedRunModule]}}
    )

    start_supervised!(
      {RelayWorker,
       name: :skeptic_http_client,
       url: url,
       relay_topic: "relay:local",
       workspace_id: "workspace-http",
       user_id: "user-skeptic",
       participant_id: "skeptic",
       participant_role: "skeptic",
       target_id: "target-skeptic-http",
       capability_id: "codex.exec.session",
       executor: {Session, [provider: :claude, driver: ScriptedRunModule]}}
    )

    assert wait_until(fn ->
             case V2.compatible_targets_for("codex.exec.session", %{}) do
               {:ok, matches} ->
                 length(RemoteExec.list_targets()) >= 2 and
                   Enum.any?(matches, &(&1.target.target_id == "target-architect-http")) and
                   Enum.any?(matches, &(&1.target.target_id == "target-skeptic-http"))

               _ ->
                 false
             end
           end)

    targets_conn = get(conn, ~p"/api/targets")

    assert %{
             "data" => [
               %{"participant_id" => "architect", "target_id" => "target-architect-http"},
               %{"participant_id" => "skeptic", "target_id" => "target-skeptic-http"}
             ]
           } = json_response(targets_conn, 200)

    create_payload = %{
      "room_id" => "room-http-1",
      "brief" => "Design a distributed collaboration protocol for two local AI clients.",
      "rules" => ["Every objection must point to a claim or evidence entry."],
      "participants" => [
        %{
          "participant_id" => "architect",
          "role" => "architect",
          "target_id" => "target-architect-http",
          "capability_id" => "codex.exec.session"
        },
        %{
          "participant_id" => "skeptic",
          "role" => "skeptic",
          "target_id" => "target-skeptic-http",
          "capability_id" => "codex.exec.session"
        }
      ]
    }

    create_conn = post(recycle(targets_conn), ~p"/api/rooms", create_payload)

    assert %{
             "data" => %{
               "room_id" => "room-http-1",
               "status" => "idle",
               "participants" => [
                 %{"participant_id" => "architect"},
                 %{"participant_id" => "skeptic"}
               ]
             }
           } = json_response(create_conn, 201)

    run_conn =
      post(recycle(create_conn), ~p"/api/rooms/room-http-1/run", %{
        "max_turns" => 6,
        "turn_timeout_ms" => 5_000
      })

    assert %{
             "data" => %{
               "room_id" => "room-http-1",
               "status" => "publication_ready",
               "context_entries" => entries,
               "disputes" => disputes,
               "turns" => turns
             }
           } = json_response(run_conn, 200)

    assert Enum.map(entries, & &1["entry_type"]) == [
             "claim",
             "evidence",
             "publish_request",
             "objection",
             "revision",
             "decision"
           ]

    assert Enum.all?(disputes, &(&1["status"] == "resolved"))
    assert Enum.map(turns, & &1["phase"]) == ["proposal", "critique", "resolution"]

    show_conn = get(recycle(run_conn), ~p"/api/rooms/room-http-1")

    assert %{
             "data" => %{
               "room_id" => "room-http-1",
               "turns" => [
                 %{"status" => "completed"},
                 %{"status" => "completed"},
                 %{"status" => "completed"}
               ]
             }
           } = json_response(show_conn, 200)

    assert get_in(json_response(show_conn, 200), ["data", "current_turn"]) == %{}

    publication_conn = get(recycle(show_conn), ~p"/api/rooms/room-http-1/publication_plan")

    assert %{
             "data" => %{
               "room_id" => "room-http-1",
               "requested" => true,
               "publications" => publications
             }
           } = json_response(publication_conn, 200)

    assert %{
             "channel" => "github",
             "capability_id" => "github.issue.create",
             "compatible_targets" => [_ | _],
             "draft" => %{"body" => github_body}
           } = Enum.find(publications, &(&1["channel"] == "github"))

    assert github_body =~ "Shared packet"
    assert github_body =~ "Conflict retention is underspecified"

    execute_conn =
      post(recycle(publication_conn), ~p"/api/rooms/room-http-1/publications", %{
        "channels" => ["github", "notion"],
        "connections" => %{
          "github" => "connection-github-http",
          "notion" => "connection-notion-http"
        },
        "bindings" => %{
          "github" => %{"repo" => "owner/repo"},
          "notion" => %{
            "parent.data_source_id" => "data-source-http",
            "title_property" => "Name"
          }
        },
        "actor_id" => "operator-http",
        "tenant_id" => "workspace-http"
      })

    assert %{
             "data" => %{"room_id" => "room-http-1", "runs" => runs}
           } = json_response(execute_conn, 200)

    assert Enum.all?(runs, &(&1["status"] == "completed"))

    history_conn = get(recycle(execute_conn), ~p"/api/rooms/room-http-1/publications")

    assert %{"data" => history} = json_response(history_conn, 200)
    assert length(history) == 2
  end

  defp wait_until(fun, attempts \\ 50)
  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(100)
      wait_until(fun, attempts - 1)
    end
  end
end
