defmodule JidoHiveConsole.WorkflowScriptTest do
  use ExUnit.Case, async: true

  alias JidoHiveConsole.WorkflowScript

  defmodule HeadlessStub do
    def dispatch(argv, opts) do
      server = Keyword.fetch!(opts, :test_server)

      Agent.get_and_update(server, fn state ->
        send(state.test_pid, {:dispatch, argv})

        case argv do
          ["room", "create" | _rest] ->
            {{:ok, %{"operation_id" => "room_create-1", "result" => %{"room_id" => state.room_id}}},
             state}

          ["room", "show" | _rest] ->
            room =
              %{
                "room_id" => state.room_id,
                "contributions" =>
                  Enum.map(state.submitted, fn text ->
                    %{
                      "participant_id" => "alice",
                      "contribution_type" => "chat",
                      "summary" => text
                    }
                  end)
              }

            {{:ok, room}, state}

          ["room", "submit" | rest] ->
            text = option_value(rest, "--text")

            result = %{
              "operation_id" => "room_submit-#{length(state.submitted) + 1}",
              "result" => %{"summary" => text}
            }

            {{:ok, result}, %{state | submitted: state.submitted ++ [text]}}

          ["room", "timeline" | _rest] ->
            entries =
              state.submitted
              |> Enum.with_index(1)
              |> Enum.map(fn {text, index} ->
                %{
                  "kind" => "contribution.recorded",
                  "event_id" => "evt-#{index}",
                  "body" => text
                }
              end)

            {{:ok, %{"entries" => entries, "next_cursor" => List.last(entries)["event_id"]}}, state}

          ["room", "run" | _rest] ->
            {{:ok, %{"operation_id" => "room_run-1", "status" => "accepted"}}, state}
        end
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
                 "--brief",
                 "Smoke workflow room",
                 "--participant-id",
                 "alice",
                 "--text",
                 "hello there",
                 "--text",
                 "second message"
               ],
               headless_module: HeadlessStub,
               test_server: server
             )

    assert result["workflow"] == "room_smoke"
    assert result["room_id"] == "room-smoke-1"
    assert Enum.map(result["submissions"], & &1["text"]) == ["hello there", "second message"]
    assert get_in(result, ["final_room", "contributions"]) |> length() == 2
    assert get_in(result, ["timeline", "entries"]) |> length() == 2

    assert_receive {:dispatch, ["room", "create" | _]}
    assert_receive {:dispatch, ["room", "show" | _]}
    assert_receive {:dispatch, ["room", "submit" | _]}
    assert_receive {:dispatch, ["room", "show" | _]}
    assert_receive {:dispatch, ["room", "submit" | _]}
    assert_receive {:dispatch, ["room", "show" | _]}
    assert_receive {:dispatch, ["room", "show" | _]}
    assert_receive {:dispatch, ["room", "timeline" | _]}
  end
end
