defmodule JidoHiveWorkerRuntime.Executor.SessionTest do
  use ExUnit.Case, async: false

  alias JidoHiveWorkerRuntime.Executor.Session
  alias JidoHiveWorkerRuntime.TestSupport.ScriptedRunModule

  test "runs an assignment through harness and decodes structured contributions" do
    assert {:ok, result} =
             Session.run(sample_assignment(),
               provider: :claude,
               driver: ScriptedRunModule,
               driver_opts: [scenario: :analyst]
             )

    assert get_in(result, ["payload", "summary"]) =~ "analysis pass"
    assert result["kind"] == "reasoning"

    assert Enum.map(get_in(result, ["payload", "context_objects"]), & &1["object_type"]) == [
             "belief",
             "note"
           ]

    assert result["execution"]["status"] == "completed"
    assert result["execution"]["provider"] == "claude"
    assert [%{"event_type" => "tool_call"}] = result["meta"]["tool_events"]
    assert Enum.any?(result["meta"]["events"], &(&1["type"] == "assistant_delta"))
  end

  test "extracts assistant_message content and raw tool lineage from codex-like events" do
    assert {:ok, result} =
             Session.run(sample_assignment(),
               provider: :codex,
               driver: ScriptedRunModule,
               driver_opts: [scenario: :codex_like]
             )

    assert get_in(result, ["payload", "summary"]) =~ "analysis pass"
    assert result["kind"] == "reasoning"
    assert result["execution"]["status"] == "completed"
    assert result["execution"]["provider"] == "codex"
    assert result["execution"]["text"] =~ "\"summary\""
    assert result["execution"]["cost"] == %{"input_tokens" => 10, "output_tokens" => 20}

    assert Enum.map(result["meta"]["tool_events"], & &1["event_type"]) == [
             "tool_call",
             "tool_result"
           ]

    assert Enum.any?(result["meta"]["events"], &(&1["type"] == "assistant_message"))
  end

  test "repairs non-json assistant output with a second strict contract pass" do
    assert {:ok, result} =
             Session.run(sample_assignment(),
               provider: :codex,
               driver: ScriptedRunModule,
               driver_opts: [scenario: :repairable]
             )

    assert get_in(result, ["payload", "summary"]) =~ "analysis pass"
    assert result["kind"] == "reasoning"
    assert result["execution"]["status"] == "completed"
    assert result["execution"]["metadata"]["repair_attempted"] == true
    assert result["execution"]["cost"] == %{"input_tokens" => 10, "output_tokens" => 20}
    assert Enum.count(result["meta"]["events"], &(&1["type"] == "assistant_message")) == 2
  end

  test "returns a failed contribution with raw execution text when repair still cannot produce json" do
    assert {:ok, result} =
             Session.run(sample_assignment(),
               provider: :codex,
               driver: ScriptedRunModule,
               driver_opts: [scenario: :unrepairable]
             )

    assert result["status"] == "failed"
    assert result["execution"]["status"] == "failed"
    assert result["execution"]["text"] =~ "not returning JSON"
    assert get_in(result, ["execution", "error", "reason"]) =~ "json_not_found"

    assert Enum.any?(get_in(result, ["payload", "artifacts"]), fn artifact ->
             artifact["title"] == "invalid_json"
           end)
  end

  defp sample_assignment do
    %{
      "id" => "asn-client-1",
      "room_id" => "room-client-1",
      "participant_id" => "analyst",
      "participant_role" => "analyst",
      "executor" => %{
        "workspace_root" => "/tmp/jido-hive-client-test",
        "provider" => "claude"
      },
      "output_contract" => %{
        "allowed_contribution_types" => ["reasoning", "artifact"],
        "allowed_object_types" => ["belief", "note", "question"],
        "allowed_relation_types" => ["derives_from", "references"],
        "authority_mode" => "advisory_only",
        "format" => "json_object"
      },
      "context" => %{
        "brief" => "Design a shared participation substrate.",
        "rules" => ["Return structured contributions only."],
        "context_objects" => []
      },
      "phase" => "analysis",
      "objective" => "Produce the first reasoning contribution."
    }
  end
end
