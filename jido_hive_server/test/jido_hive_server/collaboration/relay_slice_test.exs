defmodule JidoHiveServer.Collaboration.RelaySliceTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias Jido.Integration.V2
  alias JidoHiveClient.Executor.Session
  alias JidoHiveClient.RelayWorker
  alias JidoHiveClient.TestSupport.ScriptedRunModule
  alias JidoHiveServer.Collaboration
  alias JidoHiveServer.RemoteExec

  test "two local clients collaborate through the relay and finish a four-assignment round robin room" do
    url = relay_url()

    start_worker(:worker_01_client, url, "worker-01")
    start_worker(:worker_02_client, url, "worker-02")

    assert wait_until(fn ->
             case V2.compatible_targets_for("workspace.exec.session", %{}) do
               {:ok, matches} ->
                 length(RemoteExec.list_targets()) == 2 and length(matches) == 2

               _ ->
                 false
             end
           end)

    assert {:ok, room} =
             Collaboration.create_room(%{
               room_id: "room-relay-1",
               brief: "Develop a participation substrate for local AI workers.",
               rules: ["Return only structured contributions."],
               dispatch_policy_id: "round_robin/v2",
               dispatch_policy_config: %{
                 "phases" => [
                   %{"phase" => "analysis", "objective" => "Analyze the brief."},
                   %{"phase" => "critique", "objective" => "Critique the current context."}
                 ]
               },
               participants: worker_participants(1..2)
             })

    assert room.dispatch_state.total_slots == 4
    assert {:ok, _snapshot} = Collaboration.run_room("room-relay-1")

    assert wait_until(fn ->
             case Collaboration.fetch_room("room-relay-1") do
               {:ok, snapshot} ->
                 snapshot.status == "publication_ready" and
                   snapshot.dispatch_state.completed_slots == 4 and
                   length(snapshot.contributions) == 4

               _ ->
                 false
             end
           end)

    assert {:ok, snapshot} = Collaboration.fetch_room("room-relay-1")
    assert snapshot.status == "publication_ready"
    assert snapshot.dispatch_state.completed_slots == 4
    assert length(snapshot.assignments) == 4
    assert Enum.all?(snapshot.assignments, &(&1.status == "completed"))
    assert Enum.count(snapshot.context_objects, &(&1.object_type == "belief")) >= 2
    assert Enum.count(snapshot.context_objects, &(&1.object_type == "question")) >= 2
  end

  defp start_worker(name, url, worker_id) do
    start_supervised!(
      {RelayWorker,
       name: name,
       url: url,
       relay_topic: "relay:local",
       workspace_id: "workspace-relay",
       user_id: "user-#{worker_id}",
       participant_id: worker_id,
       participant_role: "worker",
       target_id: "target-#{worker_id}",
       capability_id: "workspace.exec.session",
       executor: {Session, [provider: :claude, driver: ScriptedRunModule]}}
    )
  end

  defp worker_participants(range) do
    Enum.map(range, fn index ->
      worker_id = "worker-0#{index}"

      %{
        participant_id: worker_id,
        participant_role: "worker",
        participant_kind: "runtime",
        target_id: "target-#{worker_id}",
        capability_id: "workspace.exec.session"
      }
    end)
  end

  defp relay_url do
    port =
      Application.fetch_env!(:jido_hive_server, JidoHiveServerWeb.Endpoint)
      |> Keyword.fetch!(:http)
      |> Keyword.fetch!(:port)

    "ws://127.0.0.1:#{port}/socket/websocket"
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
