defmodule JidoHiveServerWeb.RoomControllerTest do
  use JidoHiveServerWeb.ConnCase, async: false

  alias Jido.Integration.V2
  alias JidoHiveClient.Executor.Scripted
  alias JidoHiveClient.RelayWorker
  alias JidoHiveServer.RemoteExec

  test "creates a room, runs the first slice, and returns the room snapshot", %{conn: conn} do
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
       executor: {Scripted, [role: :architect]}}
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
       executor: {Scripted, [role: :skeptic]}}
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

    run_conn = post(recycle(create_conn), ~p"/api/rooms/room-http-1/first_slice", %{})

    assert %{
             "data" => %{
               "room_id" => "room-http-1",
               "context_entries" => entries,
               "disputes" => disputes
             }
           } = json_response(run_conn, 200)

    assert Enum.map(entries, & &1["entry_type"]) == [
             "claim",
             "evidence",
             "publish_request",
             "objection"
           ]

    assert Enum.any?(disputes, &(&1["status"] == "open"))

    show_conn = get(recycle(run_conn), ~p"/api/rooms/room-http-1")

    assert %{
             "data" => %{
               "room_id" => "room-http-1",
               "turns" => [%{"status" => "completed"}, %{"status" => "completed"}]
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
    assert github_body =~ "Conflict handling is underspecified"

    assert %{
             "channel" => "notion",
             "capability_id" => "notion.pages.create",
             "compatible_targets" => [_ | _],
             "draft" => %{"children" => notion_children}
           } = Enum.find(publications, &(&1["channel"] == "notion"))

    assert is_list(notion_children)
    assert length(notion_children) >= 3
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
