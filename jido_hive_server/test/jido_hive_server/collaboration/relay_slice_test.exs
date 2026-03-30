defmodule JidoHiveServer.Collaboration.RelaySliceTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias Jido.Integration.V2
  alias JidoHiveClient.Executor.Session
  alias JidoHiveClient.RelayWorker
  alias JidoHiveClient.TestSupport.ScriptedRunModule
  alias JidoHiveServer.Collaboration
  alias JidoHiveServer.RemoteExec
  alias JidoHiveServer.TestSupport.DelayedExecutor

  test "three local clients collaborate through the relay and finish a nine-turn round-robin plan" do
    url = relay_url()

    start_worker(:worker_01_client, url, "worker-01")
    start_worker(:worker_02_client, url, "worker-02")
    start_worker(:worker_03_client, url, "worker-03")

    assert wait_until(fn ->
             case V2.compatible_targets_for("codex.exec.session", %{}) do
               {:ok, matches} ->
                 length(RemoteExec.list_targets()) == 3 and length(matches) == 3

               _ ->
                 false
             end
           end)

    assert {:ok, room} =
             Collaboration.create_room(%{
               room_id: "room-relay-1",
               brief: "Develop a distributed collaboration protocol for multiple AI clients.",
               rules: ["Every objection must target a claim."],
               participants: worker_participants(1..3)
             })

    assert room.execution_plan.participant_count == 3
    assert room.execution_plan.planned_turn_count == 9
    assert {:ok, _snapshot} = Collaboration.run_room("room-relay-1")

    assert wait_until(fn ->
             case Collaboration.fetch_room("room-relay-1") do
               {:ok, snapshot} ->
                 snapshot.status == "publication_ready" and
                   snapshot.execution_plan.completed_turn_count == 9 and
                   Enum.all?(snapshot.disputes, &(&1.status == :resolved))

               _ ->
                 false
             end
           end)

    assert {:ok, snapshot} = Collaboration.fetch_room("room-relay-1")
    assert snapshot.status == "publication_ready"
    assert snapshot.execution_plan.completed_turn_count == 9
    assert Enum.all?(snapshot.disputes, &(&1.status == :resolved))

    assert Enum.frequencies_by(snapshot.context_entries, & &1.entry_type) == %{
             "claim" => 3,
             "evidence" => 3,
             "publish_request" => 3,
             "objection" => 3,
             "revision" => 3,
             "decision" => 3
           }

    assert Enum.map(snapshot.turns, & &1.phase) == [
             "proposal",
             "proposal",
             "proposal",
             "critique",
             "critique",
             "critique",
             "resolution",
             "resolution",
             "resolution"
           ]

    critique_turn = Enum.at(snapshot.turns, 4)
    assert critique_turn.collaboration_envelope["shared"]["instruction_log"] != []
    assert critique_turn.collaboration_envelope["shared"]["tool_call_log"] != []

    resolution_turn = Enum.at(snapshot.turns, 6)

    assert [%{"dispute_id" => "dispute:1"} | _] =
             resolution_turn.collaboration_envelope["referee"]["open_disputes"]

    assert Enum.all?(snapshot.turns, &(&1.execution["status"] == "completed"))
  end

  test "locked round-robin budget is preserved when one configured participant drops before execution" do
    url = relay_url()

    start_worker(:locked_worker_01_client, url, "worker-01")
    start_worker(:locked_worker_02_client, url, "worker-02")
    worker_03 = start_worker(:locked_worker_03_client, url, "worker-03")

    assert wait_until(fn -> length(RemoteExec.list_targets()) == 3 end)

    assert {:ok, room} =
             Collaboration.create_room(%{
               room_id: "room-relay-offline-1",
               brief: "Exercise the locked round-robin participant budget.",
               rules: ["Every objection must target a claim."],
               participants: worker_participants(1..3)
             })

    assert room.execution_plan.planned_turn_count == 9

    monitor_ref = Process.monitor(worker_03)
    :ok = GenServer.stop(worker_03)
    assert_receive {:DOWN, ^monitor_ref, :process, ^worker_03, _reason}
    assert wait_until(fn -> length(RemoteExec.list_targets()) == 2 end)

    assert {:ok, _snapshot} = Collaboration.run_room("room-relay-offline-1")
    assert {:ok, snapshot} = Collaboration.fetch_room("room-relay-offline-1")

    assert snapshot.status == "publication_ready"
    assert snapshot.execution_plan.completed_turn_count == 9
    assert length(snapshot.turns) == 9
    assert Enum.all?(snapshot.turns, &(&1.status == :completed))

    assert Enum.uniq(Enum.map(snapshot.turns, & &1.participant_id)) == ["worker-01", "worker-02"]
    assert Enum.all?(snapshot.disputes, &(&1.status == :resolved))
  end

  test "locked round-robin budget is preserved when one participant times out mid-room" do
    url = relay_url()

    start_worker(:timeout_worker_01_client, url, "worker-01")
    start_worker(:timeout_worker_02_client, url, "worker-02")

    start_worker(:timeout_worker_03_client, url, "worker-03",
      executor: {DelayedExecutor, [delay_ms: 1_500, provider: :claude, driver: ScriptedRunModule]}
    )

    assert wait_until(fn -> length(RemoteExec.list_targets()) == 3 end)

    assert {:ok, room} =
             Collaboration.create_room(%{
               room_id: "room-relay-timeout-1",
               brief: "Exercise the locked round-robin budget after a timed-out worker turn.",
               rules: ["Every objection must target a claim."],
               participants: worker_participants(1..3)
             })

    assert room.execution_plan.planned_turn_count == 9
    assert {:ok, _snapshot} = Collaboration.run_room("room-relay-timeout-1", turn_timeout_ms: 800)

    assert wait_until(fn ->
             case Collaboration.fetch_room("room-relay-timeout-1") do
               {:ok, snapshot} ->
                 snapshot.status == "publication_ready" and
                   snapshot.execution_plan.completed_turn_count == 9

               _other ->
                 false
             end
           end)

    assert {:ok, snapshot} = Collaboration.fetch_room("room-relay-timeout-1")
    assert snapshot.execution_plan.completed_turn_count == 9
    assert snapshot.execution_plan.excluded_target_ids == ["target-worker-03"]
    assert Enum.count(snapshot.turns, &(&1.status == :completed)) == 9
    assert Enum.count(snapshot.turns, &(&1.status == :abandoned)) == 1
    assert Enum.all?(snapshot.disputes, &(&1.status == :resolved))
  end

  test "job session payload preserves nested execution contracts from target registration" do
    url = relay_url()

    start_worker(:envelope_worker_01_client, url, "worker-01",
      executor:
        {Session,
         [
           provider: :codex,
           model: "gpt-5.4",
           reasoning_effort: :low,
           execution_surface: [
             surface_kind: :ssh_exec,
             transport_options: [destination: "builder.example"]
           ],
           execution_environment: [
             workspace_root: "/srv/hive",
             allowed_tools: ["git.status"],
             approval_posture: :manual,
             permission_mode: :default
           ],
           driver: ScriptedRunModule
         ]}
    )

    assert wait_until(fn -> length(RemoteExec.list_targets()) == 1 end)

    assert {:ok, room} =
             Collaboration.create_room(%{
               room_id: "room-relay-envelope-1",
               brief: "Verify session envelope carriage.",
               rules: ["Preserve the authored nested execution contract."],
               participants: worker_participants(1..1)
             })

    assert room.execution_plan.planned_turn_count == 3
    assert {:ok, _snapshot} = Collaboration.run_room("room-relay-envelope-1")

    assert wait_until(fn ->
             case Collaboration.fetch_room("room-relay-envelope-1") do
               {:ok, snapshot} -> snapshot.execution_plan.completed_turn_count == 3
               _ -> false
             end
           end)

    assert {:ok, snapshot} = Collaboration.fetch_room("room-relay-envelope-1")
    first_turn = hd(snapshot.turns)

    assert first_turn.session["execution_surface"]["surface_kind"] == "ssh_exec"

    assert first_turn.session["execution_surface"]["transport_options"]["destination"] ==
             "builder.example"

    assert first_turn.session["execution_environment"]["workspace_root"] == "/srv/hive"
    assert first_turn.session["execution_environment"]["allowed_tools"] == ["git.status"]
    assert first_turn.session["provider_options"]["model"] == "gpt-5.4"
    assert first_turn.session["provider_options"]["reasoning_effort"] == "low"
  end

  defp relay_url do
    port =
      Application.fetch_env!(:jido_hive_server, JidoHiveServerWeb.Endpoint)
      |> Keyword.fetch!(:http)
      |> Keyword.fetch!(:port)

    "ws://127.0.0.1:#{port}/socket/websocket"
  end

  defp start_worker(name, url, participant_suffix, opts \\ []) do
    driver_opts = Keyword.get(opts, :driver_opts, [])

    executor =
      Keyword.get(
        opts,
        :executor,
        {Session, [provider: :claude, driver: ScriptedRunModule, driver_opts: driver_opts]}
      )

    start_supervised!(
      Supervisor.child_spec(
        {RelayWorker,
         name: name,
         url: url,
         relay_topic: "relay:local",
         workspace_id: "workspace-local",
         user_id: "user-#{participant_suffix}",
         participant_id: participant_suffix,
         participant_role: "worker",
         target_id: "target-#{participant_suffix}",
         capability_id: "codex.exec.session",
         executor: executor},
        id: name,
        restart: :temporary
      )
    )
  end

  defp worker_participants(indexes) do
    Enum.map(indexes, fn index ->
      suffix = String.pad_leading(Integer.to_string(index), 2, "0")
      participant_id = "worker-#{suffix}"

      %{
        participant_id: participant_id,
        role: "worker",
        target_id: "target-#{participant_id}",
        capability_id: "codex.exec.session"
      }
    end)
  end

  defp wait_until(fun, attempts \\ 80)
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
