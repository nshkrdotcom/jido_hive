defmodule JidoHiveClient.EmbeddedTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Embedded

  defmodule RoomApiStub do
    @behaviour JidoHiveClient.Boundary.RoomApi

    def start_link do
      Agent.start_link(fn ->
        %{timeline: [], context_objects: [], next_event: 1, next_context: 1}
      end)
    end

    @impl true
    def fetch_timeline(opts, room_id, query_opts) do
      test_pid = Keyword.get(opts, :test_pid)
      send(test_pid, {:fetch_timeline, room_id, query_opts})

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
    def fetch_context_objects(opts, room_id) do
      test_pid = Keyword.get(opts, :test_pid)
      send(test_pid, {:fetch_context_objects, room_id})

      {:ok, Agent.get(Keyword.fetch!(opts, :server), & &1.context_objects)}
    end

    @impl true
    def submit_contribution(opts, room_id, payload) do
      test_pid = Keyword.get(opts, :test_pid)
      send(test_pid, {:submit_contribution, room_id, payload})

      Agent.update(Keyword.fetch!(opts, :server), fn state ->
        event_id = "evt-#{state.next_event}"

        context_objects =
          payload
          |> Map.get("context_objects", [])
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
          "kind" => "contribution.recorded",
          "title" => "Contribution recorded",
          "body" => payload["summary"],
          "status" => payload["status"] || "completed",
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

  test "starts with a room snapshot and allows subscription", %{embedded: embedded} do
    assert :ok = Embedded.subscribe(embedded)
    assert {:ok, snapshot} = Embedded.refresh(embedded)
    assert snapshot.room_id == "room-1"
    assert snapshot.participant.participant_id == "alice"
    assert snapshot.runtime.identity.participant_id == "alice"
  end

  test "submits chat through the mock backend and updates room state", %{embedded: embedded} do
    :ok = Embedded.subscribe(embedded)

    {:ok, contribution} =
      Embedded.submit_chat(embedded, %{
        text: "I think auth is broken because Redis timed out?"
      })

    assert contribution["summary"] == "I think auth is broken because Redis timed out?"
    assert_receive {:submit_contribution, "room-1", payload}
    assert Enum.any?(payload["context_objects"], &(&1["object_type"] == "hypothesis"))
    assert_receive {:client_runtime_event, %{type: "embedded.chat.submitted"}}

    wait_until(fn ->
      snapshot = Embedded.snapshot(embedded)
      length(snapshot.timeline) == 1 and length(snapshot.context_objects) >= 4
    end)
  end

  test "accepts a selected context object into a binding decision", %{embedded: embedded} do
    {:ok, _contribution} =
      Embedded.submit_chat(embedded, %{text: "We should roll back the registry deploy"})

    assert_receive {:submit_contribution, "room-1", _initial_payload}

    wait_until(fn -> Embedded.snapshot(embedded).context_objects != [] end)

    candidate =
      Embedded.snapshot(embedded).context_objects
      |> Enum.find(&(&1["object_type"] == "decision_candidate"))

    {:ok, contribution} = Embedded.accept_context(embedded, candidate["context_id"])

    assert contribution["authority_level"] == "binding"
    assert_receive {:submit_contribution, "room-1", acceptance_payload}
    assert Enum.any?(acceptance_payload["context_objects"], &(&1["object_type"] == "decision"))

    wait_until(fn ->
      Embedded.snapshot(embedded).context_objects
      |> Enum.any?(&(&1["object_type"] == "decision"))
    end)
  end
end
