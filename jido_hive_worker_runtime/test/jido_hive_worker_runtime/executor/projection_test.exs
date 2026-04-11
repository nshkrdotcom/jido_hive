defmodule JidoHiveWorkerRuntime.Executor.ProjectionTest do
  use ExUnit.Case, async: true

  alias Jido.Harness.ExecutionEvent
  alias JidoHiveWorkerRuntime.Executor.Projection

  test "projects execution events into normalized execution text, cost, and tool lineage" do
    run = %{run_id: "run-1"}
    session = %{session_id: "session-1", runtime_id: :asm, provider: :codex}

    event_base = %{
      runtime_id: :asm,
      run_id: "run-1",
      session_id: "session-1",
      timestamp: DateTime.utc_now()
    }

    events = [
      struct!(
        ExecutionEvent,
        Map.merge(event_base, %{
          event_id: "evt-1",
          type: :assistant_message,
          payload: %{"content" => "{\"summary\":\"done\"}"}
        })
      ),
      %ExecutionEvent{
        event_id: "evt-2",
        runtime_id: :asm,
        run_id: "run-1",
        session_id: "session-1",
        timestamp: DateTime.utc_now(),
        type: :raw,
        payload: %{
          "content" => %{
            "type" => "item.started",
            "item" => %{
              "id" => "item-1",
              "type" => "command_execution",
              "command" => "mix test"
            }
          }
        }
      },
      %ExecutionEvent{
        event_id: "evt-3",
        runtime_id: :asm,
        run_id: "run-1",
        session_id: "session-1",
        timestamp: DateTime.utc_now(),
        type: :raw,
        payload: %{
          "content" => %{
            "type" => "item.completed",
            "item" => %{
              "id" => "item-1",
              "type" => "command_execution",
              "status" => "completed",
              "command" => "mix test",
              "aggregated_output" => "ok",
              "exit_code" => 0
            }
          }
        }
      },
      %ExecutionEvent{
        event_id: "evt-4",
        runtime_id: :asm,
        run_id: "run-1",
        session_id: "session-1",
        timestamp: DateTime.utc_now(),
        type: :result,
        payload: %{
          "stop_reason" => "end_turn",
          "output" => %{"usage" => %{"input_tokens" => 10, "output_tokens" => 20}}
        }
      }
    ]

    projection = Projection.build(events, run, session)

    assert projection.execution["run_id"] == "run-1"
    assert projection.execution["session_id"] == "session-1"
    assert projection.execution["provider"] == "codex"
    assert projection.execution["status"] == "completed"
    assert projection.execution["text"] =~ "\"summary\":\"done\""
    assert projection.execution["cost"] == %{"input_tokens" => 10, "output_tokens" => 20}
    assert Enum.map(projection.tool_events, & &1["event_type"]) == ["tool_call", "tool_result"]
  end

  test "merges repair projection metadata, cost, and lineage" do
    projection = %{
      execution: %{"cost" => %{"input_tokens" => 10}, "metadata" => %{}, "text" => "broken"},
      tool_events: [%{"event_type" => "tool_call"}],
      approvals: []
    }

    repair_projection = %{
      execution: %{"cost" => %{"output_tokens" => 20}, "metadata" => %{}, "text" => "fixed"},
      tool_events: [%{"event_type" => "tool_result"}],
      approvals: [%{"event_type" => "approval_requested"}]
    }

    merged = Projection.merge_repair(projection, repair_projection, :json_not_found)

    assert merged.execution["metadata"]["repair_attempted"] == true
    assert merged.execution["metadata"]["repair_reason"] =~ "json_not_found"
    assert merged.execution["cost"] == %{"input_tokens" => 10, "output_tokens" => 20}
    assert Enum.map(merged.tool_events, & &1["event_type"]) == ["tool_call", "tool_result"]
    assert Enum.map(merged.approvals, & &1["event_type"]) == ["approval_requested"]
  end
end
