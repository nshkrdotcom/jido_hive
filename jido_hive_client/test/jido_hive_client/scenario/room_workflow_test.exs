defmodule JidoHiveClient.Scenario.RoomWorkflowTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Scenario.RoomWorkflow
  alias JidoHiveContextGraph.RoomWorkflow, as: SharedRoomWorkflow

  defmodule SharedState do
    def start_link do
      Agent.start_link(fn ->
        %{
          room_id: nil,
          name: nil,
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
        %{state | room_id: payload["id"], name: payload["name"]}
      end)

      {:ok, %{"id" => payload["id"], "name" => payload["name"], "status" => "idle"}}
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

    def fetch_room(_api_base_url, room_id, opts \\ []) do
      server = Keyword.fetch!(opts, :server)

      {:ok,
       Agent.get(server, fn state ->
         current_run_status =
           state.run_statuses
           |> Enum.at(min(max(state.run_fetch_count - 1, 0), length(state.run_statuses) - 1))

         %{
           "id" => room_id,
           "name" => state.name,
           "status" => if(current_run_status == "completed", do: "completed", else: "running"),
           "workflow_summary" => workflow_summary(state.name, current_run_status, state.messages),
           "context_objects" => context_objects(state.messages),
           "operations" => [
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

    def list_room_events(_api_base_url, _room_id, opts \\ []) do
      server = Keyword.fetch!(opts, :server)

      {:ok,
       Agent.get(server, fn state ->
         entries =
           Enum.with_index(state.messages, 1)
           |> Enum.map(fn {message, index} ->
             %{
               "event_id" => "evt-#{index}",
               "cursor" => "evt-#{index}",
               "kind" => "contribution.submitted",
               "body" => message
             }
           end)

         next_cursor =
           case length(state.messages) do
             0 -> nil
             count -> "evt-#{count}"
           end

         %{entries: entries, next_cursor: next_cursor}
       end)}
    end

    defp workflow_summary(name, current_run_status, messages) do
      duplicate_count =
        messages
        |> Enum.frequencies()
        |> Enum.reduce(0, fn {_message, count}, acc -> acc + max(count - 1, 0) end)

      publish_ready = current_run_status == "completed"

      %{
        "objective" => name,
        "stage" => if(publish_ready, do: "Ready to publish", else: "Steer active work"),
        "next_action" =>
          if(publish_ready,
            do: "Review the publication plan and submit to the selected channels",
            else: "Monitor new contributions and steer only if progress stalls"
          ),
        "blockers" => [],
        "publish_ready" => publish_ready,
        "publish_blockers" => [],
        "graph_counts" => %{
          "total" => max(length(messages), 1),
          "decisions" => 1,
          "questions" => 0,
          "contradictions" => 0,
          "duplicate_groups" => if(duplicate_count > 0, do: 1, else: 0),
          "duplicates" => duplicate_count,
          "stale" => 0
        },
        "focus_candidates" =>
          if(duplicate_count > 0,
            do: [
              %{
                "kind" => "duplicate_cluster",
                "context_id" => "ctx-1",
                "duplicate_count" => duplicate_count
              }
            ],
            else: []
          )
      }
    end

    defp context_objects(messages) do
      message_ids =
        messages
        |> Enum.with_index(1)
        |> Enum.map(fn {message, index} -> {message, "ctx-#{index}"} end)

      grouped_ids = Enum.group_by(message_ids, fn {message, _context_id} -> message end)

      Enum.with_index(messages, 1)
      |> Enum.map(fn {message, index} ->
        context_id = "ctx-#{index}"
        duplicate_context_ids = grouped_ids |> Map.fetch!(message) |> Enum.map(&elem(&1, 1))
        duplicate_size = length(duplicate_context_ids)
        duplicate_rank = Enum.find_index(duplicate_context_ids, &(&1 == context_id)) || 0

        derived =
          if duplicate_size > 1 do
            %{
              "duplicate_status" => if(duplicate_rank == 0, do: "canonical", else: "duplicate"),
              "duplicate_size" => duplicate_size,
              "duplicate_context_ids" => duplicate_context_ids,
              "canonical_context_id" => hd(duplicate_context_ids)
            }
          else
            %{}
          end

        %{
          "context_id" => context_id,
          "object_type" => "belief",
          "title" => message,
          "body" => message,
          "derived" => derived
        }
      end)
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
          "id" => room_id,
          "timeline" =>
            Enum.map(messages, fn message ->
              %{"kind" => "contribution.submitted", "body" => message}
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
          "kind" => "chat",
          "payload" => %{
            "summary" => message,
            "context_objects" => [%{"object_type" => "message", "body" => message}]
          }
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
                 "id" => "room-1",
                 "name" => "Exercise the room workflow harness."
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

    assert report.room["id"] == "room-1"
    assert get_in(report.before_run_submit, ["payload", "summary"]) == "Message before run"
    assert get_in(report.during_run_submit, ["payload", "summary"]) == "Message during run"
    assert report.run_operation["status"] == "completed"

    assert Enum.map(report.final_sync.context_objects, & &1["body"]) == [
             "Message before run",
             "Message during run"
           ]

    assert Enum.any?(report.final_sync.operations, &(&1["operation_id"] == "room_run-1"))
    assert Enum.any?(report.final_sync.entries, &(&1["body"] == "Message during run"))
    assert report.workflow_summary.stage == "Ready to publish"
    assert report.workflow_summary.next_action =~ "publication plan"
    assert report.workflow_summary.graph_counts.duplicates == 0
  end

  test "reports duplicate pressure through the shared workflow contract in duplicate-heavy rooms" do
    {:ok, server} = SharedState.start_link()

    assert {:ok, report} =
             RoomWorkflow.run(
               api_base_url: "http://127.0.0.1:4000/api",
               room_payload: %{
                 "id" => "room-duplicates-1",
                 "name" => "Collapse repeated room beliefs into one canonical operator view."
               },
               participant_id: "alice",
               participant_role: "coordinator",
               before_run_text: "Shared state belongs on the server",
               during_run_text: "Shared state belongs on the server",
               operator: {OperatorStub, [server: server]},
               session: {SessionStub, [server: server]},
               run_opts: [client_operation_id: "room_run-client-1"],
               poll_interval_ms: 1,
               max_wait_ms: 20
             )

    assert report.workflow_summary.objective ==
             "Collapse repeated room beliefs into one canonical operator view."

    assert report.workflow_summary.stage == "Ready to publish"
    assert report.workflow_summary.graph_counts.duplicates == 1

    assert report.workflow_summary.focus_candidates == [
             %{kind: "duplicate_cluster", context_id: "ctx-1", duplicate_count: 1}
           ]

    assert SharedRoomWorkflow.summary(report.final_sync.room_snapshot) == report.workflow_summary

    assert Enum.map(report.final_sync.context_objects, & &1["context_id"]) == ["ctx-1", "ctx-2"]

    assert Enum.map(
             report.final_sync.context_objects,
             &get_in(&1, ["derived", "duplicate_status"])
           ) ==
             ["canonical", "duplicate"]
  end
end
