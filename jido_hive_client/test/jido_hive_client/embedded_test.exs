defmodule JidoHiveClient.EmbeddedTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Embedded

  defmodule RoomApiStub do
    @behaviour JidoHiveClient.Boundary.RoomApi

    def start_link do
      Agent.start_link(fn ->
        %{
          room_snapshot: %{
            "id" => "room-1",
            "name" => "Embedded room",
            "status" => "running",
            "participants" => []
          },
          timeline: [],
          context_objects: [],
          next_event: 1,
          next_context: 1
        }
      end)
    end

    @impl true
    def fetch_room(opts, room_id) do
      test_pid = Keyword.get(opts, :test_pid)
      send(test_pid, {:fetch_room, room_id})

      {:ok,
       Agent.get(Keyword.fetch!(opts, :server), fn state ->
         Map.merge(state.room_snapshot, %{
           "timeline" => state.timeline,
           "context_objects" => state.context_objects
         })
       end)}
    end

    @impl true
    def list_events(opts, room_id, query_opts) do
      test_pid = Keyword.get(opts, :test_pid)
      send(test_pid, {:list_events, room_id, query_opts})

      after_cursor = Keyword.get(query_opts, :after)

      result =
        Agent.get(Keyword.fetch!(opts, :server), fn state ->
          entries =
            case after_cursor do
              nil -> state.timeline
              cursor -> drop_after(state.timeline, cursor)
            end

          %{entries: entries, next_cursor: next_cursor(state.timeline)}
        end)

      {:ok, result}
    end

    @impl true
    def submit_contribution(opts, room_id, payload) do
      test_pid = Keyword.get(opts, :test_pid)
      send(test_pid, {:submit_contribution, room_id, payload})

      Agent.update(Keyword.fetch!(opts, :server), fn state ->
        event_id = "evt-#{state.next_event}"

        context_objects =
          payload
          |> get_in(["payload", "context_objects"])
          |> Kernel.||([])
          |> Enum.with_index(state.next_context)
          |> Enum.map(fn {context_object, index} ->
            context_object
            |> Map.put("context_id", "ctx-#{index}")
            |> Map.put("authored_by", %{"participant_id" => payload["participant_id"]})
          end)

        timeline_entry = %{
          "entry_id" => event_id,
          "cursor" => event_id,
          "event_id" => event_id,
          "kind" => "contribution.submitted",
          "title" => "Contribution recorded",
          "body" => get_in(payload, ["payload", "summary"]),
          "status" => get_in(payload, ["meta", "status"]) || "completed",
          "metadata" => payload
        }

        %{
          state
          | timeline: state.timeline ++ [timeline_entry],
            context_objects: state.context_objects ++ context_objects,
            next_event: state.next_event + 1,
            next_context: state.next_context + length(context_objects)
        }
      end)

      {:ok, %{"data" => %{"room_id" => room_id}}}
    end

    defp drop_after(entries, cursor) do
      case Enum.find_index(entries, &(&1["cursor"] == cursor or &1["event_id"] == cursor)) do
        nil -> entries
        index -> Enum.drop(entries, index + 1)
      end
    end

    defp next_cursor([]), do: nil
    defp next_cursor(entries), do: List.last(entries)["cursor"]
  end

  defmodule SubmitOkSyncFailRoomApiStub do
    @behaviour JidoHiveClient.Boundary.RoomApi

    @impl true
    def fetch_room(opts, room_id) do
      send(Keyword.fetch!(opts, :test_pid), {:sync_fail_fetch_room, room_id})

      {:ok,
       %{
         "id" => room_id,
         "name" => "Sync failure room",
         "status" => "running",
         "participants" => []
       }}
    end

    @impl true
    def list_events(opts, room_id, query_opts) do
      send(Keyword.fetch!(opts, :test_pid), {:sync_fail_list_events, room_id, query_opts})
      {:error, :sync_failed}
    end

    @impl true
    def submit_contribution(opts, room_id, payload) do
      send(Keyword.fetch!(opts, :test_pid), {:submit_contribution, room_id, payload})
      {:ok, %{"data" => %{"room_id" => room_id}}}
    end
  end

  defmodule BlockingSyncRoomApiStub do
    @behaviour JidoHiveClient.Boundary.RoomApi

    @impl true
    def fetch_room(_opts, room_id) do
      {:ok,
       %{
         "id" => room_id,
         "name" => "Blocking room",
         "status" => "running",
         "participants" => []
       }}
    end

    @impl true
    def list_events(opts, room_id, query_opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:blocking_list_events, self(), room_id, query_opts})

      receive do
        :release_list_events ->
          {:ok, %{entries: [], next_cursor: Keyword.get(query_opts, :after)}}
      after
        5_000 ->
          {:ok, %{entries: [], next_cursor: Keyword.get(query_opts, :after)}}
      end
    end

    @impl true
    def submit_contribution(opts, room_id, payload) do
      send(Keyword.fetch!(opts, :test_pid), {:submit_contribution, room_id, payload})
      {:ok, %{"data" => %{"room_id" => room_id}}}
    end
  end

  defmodule MissingRoomApiStub do
    @behaviour JidoHiveClient.Boundary.RoomApi

    def start_link do
      Agent.start_link(fn -> %{room_fetches: 0} end)
    end

    @impl true
    def fetch_room(opts, room_id) do
      server = Keyword.fetch!(opts, :server)
      test_pid = Keyword.fetch!(opts, :test_pid)

      count =
        Agent.get_and_update(server, fn state ->
          next = state.room_fetches + 1
          {next, %{state | room_fetches: next}}
        end)

      send(test_pid, {:missing_fetch_room, room_id, count})
      {:error, :room_not_found}
    end

    @impl true
    def list_events(_opts, _room_id, _query_opts),
      do: flunk("list_events should not run after a room_not_found fetch_room response")

    @impl true
    def submit_contribution(_opts, _room_id, _payload), do: {:error, :room_not_found}
  end

  defp wait_until(fun, attempts \\ 20)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: flunk("condition not met")

  defp flush_mailbox do
    receive do
      _message -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  setup do
    {:ok, server} = RoomApiStub.start_link()

    {:ok, embedded} =
      Embedded.start_link(
        room_id: "room-1",
        participant_id: "alice",
        participant_role: "operator",
        room_api: {RoomApiStub, [server: server, test_pid: self()]},
        poll_interval_ms: 5_000
      )

    %{embedded: embedded, server: server}
  end

  test "refresh snapshot includes room metadata from the room api", %{embedded: embedded} do
    assert {:ok, snapshot} = Embedded.refresh(embedded)
    assert snapshot["status"] == "running"
    assert snapshot["id"] == "room-1"
    assert snapshot["name"] == "Embedded room"
  end

  test "poll uses explicit room fetch and event listing when no new timeline entries arrive", %{
    embedded: embedded
  } do
    Process.sleep(20)
    flush_mailbox()

    assert {:ok, _snapshot} = Embedded.refresh(embedded)
    assert_receive {:fetch_room, "room-1"}
    assert_receive {:list_events, "room-1", [after: nil]}

    flush_mailbox()
    send(embedded, :poll)

    assert_receive {:fetch_room, "room-1"}
    assert_receive {:list_events, "room-1", [after: _cursor]}
  end

  test "subscribe pushes the current snapshot after hydration", %{embedded: embedded} do
    assert {:ok, snapshot} = Embedded.refresh(embedded)
    assert snapshot["id"] == "room-1"
    assert snapshot["participant"].participant_id == "alice"
    assert snapshot["session_state"].identity.participant_id == "alice"
    flush_mailbox()

    assert :ok = Embedded.subscribe(embedded)
    assert_receive {:room_session_snapshot, "room-1", subscribed_snapshot}
    assert subscribed_snapshot["id"] == "room-1"
    assert subscribed_snapshot["last_sync_at"] == snapshot["last_sync_at"]
    assert subscribed_snapshot["status"] == "running"
  end

  test "subscribe does not emit a placeholder snapshot before first hydration" do
    {:ok, embedded} =
      Embedded.start_link(
        room_id: "room-1",
        participant_id: "alice",
        participant_role: "operator",
        room_api: {BlockingSyncRoomApiStub, [test_pid: self()]},
        poll_interval_ms: 5_000
      )

    assert_receive {:blocking_list_events, blocker, "room-1", [after: nil]}

    assert :ok = Embedded.subscribe(embedded)
    refute_receive {:room_session_snapshot, "room-1", _snapshot}, 80

    send(blocker, :release_list_events)

    assert_receive {:room_session_snapshot, "room-1", hydrated_snapshot}
    assert hydrated_snapshot["status"] == "running"
  end

  test "submits chat through the mock backend and updates room state", %{embedded: embedded} do
    :ok = Embedded.subscribe(embedded)

    {:ok, contribution} =
      Embedded.submit_chat(embedded, %{
        text: "I think auth is broken because Redis timed out?"
      })

    assert get_in(contribution, ["payload", "summary"]) ==
             "I think auth is broken because Redis timed out?"

    assert_receive {:submit_contribution, "room-1", payload}

    assert Enum.any?(
             get_in(payload, ["payload", "context_objects"]),
             &(&1["object_type"] == "hypothesis")
           )

    assert_receive {:client_runtime_event, %{type: "embedded.chat.submitted"}}

    wait_until(fn ->
      snapshot = Embedded.snapshot(embedded)
      length(snapshot["timeline"]) == 1 and length(snapshot["context_objects"]) >= 4
    end)
  end

  test "accepts a selected context object into a binding decision", %{embedded: embedded} do
    {:ok, _contribution} =
      Embedded.submit_chat(embedded, %{text: "We should roll back the registry deploy"})

    assert_receive {:submit_contribution, "room-1", _initial_payload}

    wait_until(fn -> Embedded.snapshot(embedded)["context_objects"] != [] end)

    candidate =
      Embedded.snapshot(embedded)["context_objects"]
      |> Enum.find(&(&1["object_type"] == "decision_candidate"))

    {:ok, contribution} = Embedded.accept_context(embedded, candidate["context_id"])

    assert get_in(contribution, ["meta", "authority_level"]) == "binding"
    assert_receive {:submit_contribution, "room-1", acceptance_payload}

    assert Enum.any?(
             get_in(acceptance_payload, ["payload", "context_objects"]),
             &(&1["object_type"] == "decision")
           )

    assert Enum.find(
             get_in(acceptance_payload, ["payload", "context_objects"]),
             &(&1["object_type"] == "decision")
           )[
             "relations"
           ] == [
             %{"relation" => "derives_from", "target_id" => candidate["context_id"]}
           ]

    wait_until(fn ->
      Embedded.snapshot(embedded)["context_objects"]
      |> Enum.any?(&(&1["object_type"] == "decision"))
    end)
  end

  test "submits selected relation context through the embedded chat path", %{embedded: embedded} do
    {:ok, _contribution} =
      Embedded.submit_chat(embedded, %{
        text: "I think auth is broken",
        selected_context_id: "ctx-root",
        selected_relation: "references"
      })

    assert_receive {:submit_contribution, "room-1", payload}

    assert Enum.find(
             get_in(payload, ["payload", "context_objects"]),
             &(&1["object_type"] == "hypothesis")
           )[
             "relations"
           ] == [
             %{"relation" => "references", "target_id" => "ctx-root"}
           ]
  end

  test "submits plain chat when selected relation mode is none", %{embedded: embedded} do
    {:ok, _contribution} =
      Embedded.submit_chat(embedded, %{
        text: "I think auth is broken",
        selected_context_id: "ctx-root",
        selected_relation: "none"
      })

    assert_receive {:submit_contribution, "room-1", payload}

    refute Enum.any?(get_in(payload, ["payload", "context_objects"]), fn object ->
             Map.has_key?(object, "relations")
           end)
  end

  test "submit_chat succeeds even when the post-submit sync fails" do
    {:ok, embedded} =
      Embedded.start_link(
        room_id: "room-1",
        participant_id: "alice",
        participant_role: "operator",
        room_api: {SubmitOkSyncFailRoomApiStub, [test_pid: self()]},
        poll_interval_ms: 60_000
      )

    assert {:ok, contribution} =
             Embedded.submit_chat(embedded, %{
               text: "Acknowledge now, sync later"
             })

    assert get_in(contribution, ["payload", "summary"]) == "Acknowledge now, sync later"
    assert_receive {:submit_contribution, "room-1", payload}
    assert get_in(payload, ["payload", "summary"]) == "Acknowledge now, sync later"
  end

  test "submit_chat stays responsive while a poll sync is in flight" do
    {:ok, embedded} =
      Embedded.start_link(
        room_id: "room-1",
        participant_id: "alice",
        participant_role: "operator",
        room_api: {BlockingSyncRoomApiStub, [test_pid: self()]},
        poll_interval_ms: 60_000
      )

    assert_receive {:blocking_list_events, blocker, "room-1", _query_opts}

    task =
      Task.async(fn ->
        Embedded.submit_chat(embedded, %{text: "Submit while sync is blocked"})
      end)

    assert {:ok, contribution} = Task.await(task, 500)
    assert get_in(contribution, ["payload", "summary"]) == "Submit while sync is blocked"
    assert_receive {:submit_contribution, "room-1", payload}
    assert get_in(payload, ["payload", "summary"]) == "Submit while sync is blocked"

    send(blocker, :release_list_events)
  end

  test "submit_chat_async broadcasts accepted and completed snapshots to subscribers", %{
    embedded: embedded
  } do
    assert {:ok, _snapshot} = Embedded.refresh(embedded)
    flush_mailbox()

    assert :ok = Embedded.subscribe(embedded)
    assert_receive {:room_session_snapshot, "room-1", _initial_snapshot}

    assert {:ok, %{"operation_id" => operation_id, "status" => "accepted"}} =
             Embedded.submit_chat_async(embedded, %{text: "Broadcast the new snapshot"})

    assert_receive {:room_session_snapshot, "room-1", accepted_snapshot}

    assert Enum.any?(accepted_snapshot["operations"], fn operation ->
             operation["operation_id"] == operation_id and
               operation["status"] in ["accepted", "preparing", "sending", "server_acknowledged"]
           end)

    wait_until(fn ->
      Embedded.snapshot(embedded)["operations"]
      |> Enum.any?(fn operation ->
        operation["operation_id"] == operation_id and operation["status"] == "completed"
      end)
    end)

    assert_receive {:room_session_snapshot, "room-1", _later_snapshot}

    wait_until(fn ->
      Embedded.snapshot(embedded)["context_objects"]
      |> Enum.any?(fn object -> object["body"] == "Broadcast the new snapshot" end)
    end)
  end

  test "quiet syncs back off their next poll delay" do
    {:ok, server} = RoomApiStub.start_link()

    {:ok, embedded} =
      Embedded.start_link(
        room_id: "room-1",
        participant_id: "alice",
        participant_role: "operator",
        room_api: {RoomApiStub, [server: server, test_pid: self()]},
        poll_interval_ms: 10
      )

    wait_until(fn ->
      state = :sys.get_state(embedded)
      state.polling.idle_count >= 2 and state.polling.next_delay_ms >= 40
    end)
  end

  test "quiet syncs do not rebroadcast unchanged snapshots" do
    {:ok, server} = RoomApiStub.start_link()

    {:ok, embedded} =
      Embedded.start_link(
        room_id: "room-1",
        participant_id: "alice",
        participant_role: "operator",
        room_api: {RoomApiStub, [server: server, test_pid: self()]},
        poll_interval_ms: 10
      )

    wait_until(fn ->
      state = :sys.get_state(embedded)

      not is_nil(state.last_sync_at) and state.sync_task_pid == nil and
        state.polling.idle_count >= 1
    end)

    assert :ok = Embedded.subscribe(embedded)
    assert_receive {:room_session_snapshot, "room-1", _snapshot}
    flush_mailbox()

    refute_receive {:room_session_snapshot, "room-1", _snapshot}, 80
  end

  test "stops polling after repeated room_not_found failures" do
    {:ok, server} = MissingRoomApiStub.start_link()

    {:ok, embedded} =
      Embedded.start_link(
        room_id: "missing-room",
        participant_id: "alice",
        participant_role: "operator",
        room_api: {MissingRoomApiStub, [server: server, test_pid: self()]},
        poll_interval_ms: 10
      )

    assert_receive {:missing_fetch_room, "missing-room", 1}, 500
    assert_receive {:missing_fetch_room, "missing-room", 2}, 500
    assert_receive {:missing_fetch_room, "missing-room", 3}, 500

    wait_until(fn -> Embedded.snapshot(embedded)["last_error"] == :room_not_found end)
    Process.sleep(80)

    assert Agent.get(server, & &1.room_fetches) == 3
  end
end
