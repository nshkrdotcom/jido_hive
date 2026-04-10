defmodule JidoHiveClient.Scenario.RoomWorkflowTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Scenario.RoomWorkflow

  defmodule SharedState do
    def start_link do
      Agent.start_link(fn ->
        %{
          room_id: nil,
          brief: nil,
          messages: [],
          run_statuses: ["accepted", "running", "completed"],
          run_fetch_count: 0
        }
      end)
    end
  end

  defmodule OperatorStub do
    def create_room(_api_base_url, payload, opts \\ []) do
      server = Keyword.fetch!(opts, :server)

      Agent.update(server, fn state ->
        %{state | room_id: payload["room_id"], brief: payload["brief"]}
      end)

      {:ok, %{"room_id" => payload["room_id"], "status" => "idle"}}
    end

    def start_room_run_operation(_api_base_url, room_id, opts \\ []) do
      {:ok,
       %{
         "room_id" => room_id,
         "operation_id" => "room_run-1",
         "client_operation_id" => Keyword.get(opts, :client_operation_id, "room_run-client-1"),
         "status" => "accepted"
       }}
    end

    def fetch_room_run_operation(_api_base_url, room_id, operation_id, opts \\ []) do
      server = Keyword.fetch!(opts, :server)

      Agent.get_and_update(server, fn state ->
        index = min(state.run_fetch_count, length(state.run_statuses) - 1)
        status = Enum.at(state.run_statuses, index)

        operation = %{
          "room_id" => room_id,
          "operation_id" => operation_id,
          "client_operation_id" => "room_run-client-1",
          "status" => status
        }

        {operation, %{state | run_fetch_count: state.run_fetch_count + 1}}
      end)
      |> then(&{:ok, &1})
    end

    def fetch_room_sync(_api_base_url, room_id, opts \\ []) do
      server = Keyword.fetch!(opts, :server)

      {:ok,
       Agent.get(server, fn state ->
         current_run_status =
           state.run_statuses
           |> Enum.at(min(max(state.run_fetch_count - 1, 0), length(state.run_statuses) - 1))

         %{
           room_snapshot: %{
             "room_id" => room_id,
             "status" =>
               if(current_run_status == "completed", do: "publication_ready", else: "running")
           },
           entries:
             Enum.with_index(state.messages, 1)
             |> Enum.map(fn {message, index} ->
               %{
                 "event_id" => "evt-#{index}",
                 "cursor" => "evt-#{index}",
                 "kind" => "contribution.recorded",
                 "body" => message
               }
             end),
           next_cursor:
             case length(state.messages) do
               0 -> nil
               count -> "evt-#{count}"
             end,
           context_objects:
             Enum.map(state.messages, fn message ->
               %{
                 "context_id" => "ctx-#{message}",
                 "object_type" => "message",
                 "body" => message
               }
             end),
           operations: [
             %{
               "operation_id" => "room_run-1",
               "client_operation_id" => "room_run-client-1",
               "kind" => "room_run",
               "status" => current_run_status
             }
           ]
         }
       end)}
    end
  end

  defmodule SessionStub do
    def start_link(opts) do
      Agent.start_link(fn ->
        %{
          room_id: Keyword.fetch!(opts, :room_id),
          participant_id: Keyword.fetch!(opts, :participant_id),
          shared_server: Keyword.fetch!(opts, :server)
        }
      end)
    end

    def refresh(session), do: {:ok, snapshot(session)}

    def snapshot(session) do
      Agent.get(session, fn %{room_id: room_id, shared_server: shared_server} ->
        messages = Agent.get(shared_server, & &1.messages)

        %{
          "room_id" => room_id,
          "timeline" =>
            Enum.map(messages, fn message ->
              %{"kind" => "contribution.recorded", "body" => message}
            end),
          "context_objects" =>
            Enum.map(messages, fn message ->
              %{"object_type" => "message", "body" => message}
            end),
          "operations" => []
        }
      end)
    end

    def submit_chat(session, attrs) do
      Agent.get(session, fn %{
                              room_id: room_id,
                              participant_id: participant_id,
                              shared_server: shared_server
                            } ->
        message = Map.get(attrs, :text) || Map.get(attrs, "text")

        Agent.update(shared_server, fn state ->
          %{state | messages: state.messages ++ [message]}
        end)

        %{
          "room_id" => room_id,
          "participant_id" => participant_id,
          "contribution_type" => "chat",
          "summary" => message,
          "context_objects" => [%{"object_type" => "message", "body" => message}]
        }
      end)
      |> then(&{:ok, &1})
    end

    def shutdown(session), do: GenServer.stop(session)
  end

  test "runs a non-TUI room workflow through the shared operator and session layers" do
    {:ok, server} = SharedState.start_link()

    assert {:ok, report} =
             RoomWorkflow.run(
               api_base_url: "http://127.0.0.1:4000/api",
               room_payload: %{
                 "room_id" => "room-1",
                 "brief" => "Exercise the room workflow harness."
               },
               participant_id: "alice",
               participant_role: "coordinator",
               before_run_text: "Message before run",
               during_run_text: "Message during run",
               operator: {OperatorStub, [server: server]},
               session: {SessionStub, [server: server]},
               run_opts: [client_operation_id: "room_run-client-1"],
               poll_interval_ms: 1,
               max_wait_ms: 20
             )

    assert report.transitions == [
             :room_created,
             :room_refreshed,
             :chat_submitted_before_run,
             :run_started,
             :chat_submitted_during_run,
             :run_completed,
             :room_synced
           ]

    assert report.room["room_id"] == "room-1"
    assert report.before_run_submit["summary"] == "Message before run"
    assert report.during_run_submit["summary"] == "Message during run"
    assert report.run_operation["status"] == "completed"

    assert Enum.map(report.final_sync.context_objects, & &1["body"]) == [
             "Message before run",
             "Message during run"
           ]

    assert Enum.any?(report.final_sync.operations, &(&1["operation_id"] == "room_run-1"))
    assert Enum.any?(report.final_sync.entries, &(&1["body"] == "Message during run"))
  end
end
