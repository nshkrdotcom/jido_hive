defmodule JidoHiveConsole.WorkflowScriptTest do
  use ExUnit.Case, async: true

  alias JidoHiveConsole.WorkflowScript

  defmodule BootstrapStub do
    def start_cli_dependencies do
      send(self(), :bootstrap_started)
      :ok
    end
  end

  defmodule HeadlessStub do
    def dispatch(argv, opts) do
      server = Keyword.fetch!(opts, :test_server)

      Agent.get_and_update(server, fn state ->
        send(state.test_pid, {:dispatch, argv})
        dispatch_result(argv, state)
      end)
    end

    defp option_value(argv, flag) do
      argv
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.find_value(fn
        [^flag, value] -> value
        _other -> nil
      end)
    end

    defp dispatch_result(["room", "create" | _rest], state) do
      {{:ok, %{"operation_id" => "room_create-1", "result" => %{"id" => state.room_id}}}, state}
    end

    defp dispatch_result(["room", "show" | _rest], state) do
      {{:ok, %{"id" => state.room_id, "contributions" => contributions(state)}}, state}
    end

    defp dispatch_result(["room", "submit" | rest], state) do
      text = option_value(rest, "--text")

      result = %{
        "operation_id" => "room_submit-#{length(state.submitted) + 1}",
        "result" => %{"summary" => text}
      }

      {{:ok, result}, %{state | submitted: state.submitted ++ [text]}}
    end

    defp dispatch_result(["room", "timeline" | _rest], state) do
      entries = timeline_entries(state)
      {{:ok, %{"entries" => entries, "next_cursor" => List.last(entries)["event_id"]}}, state}
    end

    defp dispatch_result(["room", "run" | _rest], state) do
      {{:ok, %{"operation_id" => "room_run-1", "status" => "accepted"}}, state}
    end

    defp contributions(state) do
      Enum.map(state.submitted, fn text ->
        %{
          "participant_id" => "alice",
          "kind" => "chat",
          "payload" => %{"summary" => text}
        }
      end)
    end

    defp timeline_entries(state) do
      state.submitted
      |> Enum.with_index(1)
      |> Enum.map(fn {text, index} ->
        %{
          "kind" => "contribution.submitted",
          "event_id" => "evt-#{index}",
          "body" => text
        }
      end)
    end
  end

  test "room-smoke workflow scripts create, submit, and inspect through the headless client" do
    test_pid = self()

    {:ok, server} =
      Agent.start_link(fn ->
        %{room_id: "room-smoke-1", submitted: [], test_pid: test_pid}
      end)

    assert {:ok, result} =
             WorkflowScript.run(
               [
                 "--api-base-url",
                 "http://127.0.0.1:4000/api",
                 "--room-id",
                 "room-smoke-1",
                 "--name",
                 "Smoke workflow room",
                 "--participant-id",
                 "alice",
                 "--text",
                 "hello there",
                 "--text",
                 "second message"
               ],
               bootstrap_module: BootstrapStub,
               headless_module: HeadlessStub,
               test_server: server
             )

    assert result["workflow"] == "room_smoke"
    assert result["room_id"] == "room-smoke-1"
    assert result["name"] == "Smoke workflow room"
    assert Enum.map(result["submissions"], & &1["text"]) == ["hello there", "second message"]
    assert get_in(result, ["final_room", "contributions"]) |> length() == 2
    assert get_in(result, ["timeline", "entries"]) |> length() == 2

    assert_received :bootstrap_started
    assert_receive {:dispatch, ["room", "create" | _]}
    assert_receive {:dispatch, ["room", "show" | _]}
    assert_receive {:dispatch, ["room", "submit" | _]}
    assert_receive {:dispatch, ["room", "show" | _]}
    assert_receive {:dispatch, ["room", "submit" | _]}
    assert_receive {:dispatch, ["room", "show" | _]}
    assert_receive {:dispatch, ["room", "show" | _]}
    assert_receive {:dispatch, ["room", "timeline" | _]}
  end

  test "room-smoke workflow accepts mode flags and resolves the local api base url" do
    test_pid = self()

    {:ok, server} =
      Agent.start_link(fn ->
        %{room_id: "room-smoke-local", submitted: [], test_pid: test_pid}
      end)

    assert {:ok, result} =
             WorkflowScript.run(
               [
                 "--local",
                 "--room-id",
                 "room-smoke-local",
                 "--text",
                 "hello from local mode"
               ],
               bootstrap_module: BootstrapStub,
               headless_module: HeadlessStub,
               test_server: server
             )

    assert result["api_base_url"] == "http://127.0.0.1:4000/api"
    assert result["room_id"] == "room-smoke-local"
    assert Enum.map(result["submissions"], & &1["text"]) == ["hello from local mode"]
  end

  test "explicit api base url wins over mode flags" do
    test_pid = self()

    {:ok, server} =
      Agent.start_link(fn ->
        %{room_id: "room-smoke-explicit", submitted: [], test_pid: test_pid}
      end)

    assert {:ok, result} =
             WorkflowScript.run(
               [
                 "--prod",
                 "--api-base-url",
                 "https://example.com/api",
                 "--room-id",
                 "room-smoke-explicit",
                 "--text",
                 "hello from explicit mode"
               ],
               bootstrap_module: BootstrapStub,
               headless_module: HeadlessStub,
               test_server: server
             )

    assert result["api_base_url"] == "https://example.com/api"
  end
end
