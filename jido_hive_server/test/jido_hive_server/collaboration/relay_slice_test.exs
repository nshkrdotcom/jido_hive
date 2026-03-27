defmodule JidoHiveServer.Collaboration.RelaySliceTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias Jido.Integration.V2
  alias JidoHiveClient.Executor.Session
  alias JidoHiveClient.RelayWorker
  alias JidoHiveClient.TestSupport.ScriptedRunModule
  alias JidoHiveServer.Collaboration
  alias JidoHiveServer.RemoteExec

  test "two local clients collaborate through the relay, share tool lineage, and finish publication-ready" do
    port =
      Application.fetch_env!(:jido_hive_server, JidoHiveServerWeb.Endpoint)
      |> Keyword.fetch!(:http)
      |> Keyword.fetch!(:port)

    url = "ws://127.0.0.1:#{port}/socket/websocket"

    start_supervised!(
      {RelayWorker,
       name: :architect_client,
       url: url,
       relay_topic: "relay:local",
       workspace_id: "workspace-local",
       user_id: "user-architect",
       participant_id: "architect",
       participant_role: "architect",
       target_id: "target-architect",
       capability_id: "codex.exec.session",
       executor: {Session, [provider: :claude, driver: ScriptedRunModule]}}
    )

    start_supervised!(
      {RelayWorker,
       name: :skeptic_client,
       url: url,
       relay_topic: "relay:local",
       workspace_id: "workspace-local",
       user_id: "user-skeptic",
       participant_id: "skeptic",
       participant_role: "skeptic",
       target_id: "target-skeptic",
       capability_id: "codex.exec.session",
       executor: {Session, [provider: :claude, driver: ScriptedRunModule]}}
    )

    assert wait_until(fn ->
             case V2.compatible_targets_for("codex.exec.session", %{}) do
               {:ok, matches} ->
                 length(RemoteExec.list_targets()) == 2 and length(matches) == 2

               _ ->
                 false
             end
           end)

    assert {:ok, room} =
             Collaboration.create_room(%{
               room_id: "room-relay-1",
               brief: "Develop a distributed collaboration protocol for two AI clients.",
               rules: ["Every objection must target a claim."],
               participants: [
                 %{
                   participant_id: "architect",
                   role: "architect",
                   target_id: "target-architect",
                   capability_id: "codex.exec.session"
                 },
                 %{
                   participant_id: "skeptic",
                   role: "skeptic",
                   target_id: "target-skeptic",
                   capability_id: "codex.exec.session"
                 }
               ]
             })

    assert room.room_id == "room-relay-1"
    assert {:ok, _snapshot} = Collaboration.run_room("room-relay-1", max_turns: 6)

    assert wait_until(fn ->
             case Collaboration.fetch_room("room-relay-1") do
               {:ok, snapshot} ->
                 snapshot.status == "publication_ready" and
                   length(snapshot.turns) == 3 and
                   Enum.all?(snapshot.disputes, &(&1.status == :resolved))

               _ ->
                 false
             end
           end)

    assert {:ok, snapshot} = Collaboration.fetch_room("room-relay-1")
    assert snapshot.status == "publication_ready"
    assert Enum.all?(snapshot.disputes, &(&1.status == :resolved))

    assert Enum.map(snapshot.context_entries, & &1.entry_type) == [
             "claim",
             "evidence",
             "publish_request",
             "objection",
             "revision",
             "decision"
           ]

    assert Enum.map(snapshot.turns, & &1.phase) == ["proposal", "critique", "resolution"]

    critique_turn = Enum.at(snapshot.turns, 1)
    assert critique_turn.collaboration_envelope["shared"]["instruction_log"] != []
    assert critique_turn.collaboration_envelope["shared"]["tool_call_log"] != []

    resolution_turn = Enum.at(snapshot.turns, 2)

    assert [%{"dispute_id" => "dispute:1"}] =
             resolution_turn.collaboration_envelope["referee"]["open_disputes"]

    assert Enum.all?(snapshot.turns, &(&1.execution["status"] == "completed"))
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
