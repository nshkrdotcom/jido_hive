defmodule JidoHiveClient.Executor.SessionTest do
  use ExUnit.Case, async: false

  alias JidoHiveClient.Executor.Session
  alias JidoHiveClient.TestSupport.ScriptedRunModule

  test "runs a collaboration turn through harness and decodes structured actions" do
    assert {:ok, result} =
             Session.run(sample_job(),
               provider: :claude,
               driver: ScriptedRunModule,
               driver_opts: [scenario: :architect]
             )

    assert result["summary"] =~ "architect proposed"
    assert Enum.map(result["actions"], & &1["op"]) == ["CLAIM", "EVIDENCE", "PUBLISH"]
    assert result["execution"]["status"] == "completed"
    assert result["execution"]["provider"] == "claude"
    assert [%{"event_type" => "tool_call"}] = result["tool_events"]
    assert Enum.any?(result["events"], &(&1["type"] == "assistant_delta"))
  end

  test "extracts assistant_message content and raw tool lineage from codex-like events" do
    assert {:ok, result} =
             Session.run(sample_job(),
               provider: :codex,
               driver: ScriptedRunModule,
               driver_opts: [scenario: :codex_like]
             )

    assert result["summary"] =~ "architect proposed"
    assert Enum.map(result["actions"], & &1["op"]) == ["CLAIM", "EVIDENCE", "PUBLISH"]
    assert result["execution"]["status"] == "completed"
    assert result["execution"]["provider"] == "codex"
    assert result["execution"]["text"] =~ "\"summary\""
    assert result["execution"]["cost"] == %{"input_tokens" => 10, "output_tokens" => 20}

    assert Enum.map(result["tool_events"], & &1["event_type"]) == ["tool_call", "tool_result"]
    assert Enum.any?(result["events"], &(&1["type"] == "assistant_message"))
  end

  test "repairs non-json assistant output with a second strict contract pass" do
    assert {:ok, result} =
             Session.run(sample_job(),
               provider: :codex,
               driver: ScriptedRunModule,
               driver_opts: [scenario: :repairable]
             )

    assert result["summary"] =~ "architect proposed"
    assert Enum.map(result["actions"], & &1["op"]) == ["CLAIM", "EVIDENCE", "PUBLISH"]
    assert result["execution"]["status"] == "completed"
    assert result["execution"]["metadata"]["repair_attempted"] == true
    assert result["execution"]["cost"] == %{"input_tokens" => 10, "output_tokens" => 20}
    assert Enum.count(result["events"], &(&1["type"] == "assistant_message")) == 2
  end

  defp sample_job do
    %{
      "job_id" => "job-client-1",
      "room_id" => "room-client-1",
      "participant_id" => "architect",
      "participant_role" => "architect",
      "session" => %{
        "workspace_root" => "/tmp/jido-hive-client-test",
        "provider" => "claude"
      },
      "collaboration_envelope" => %{
        "schema_version" => "jido_hive/collab_envelope.v1",
        "room" => %{
          "room_id" => "room-client-1",
          "brief" => "Design a shared collaboration envelope.",
          "rules" => ["Every objection must target a claim or dispute."]
        },
        "referee" => %{
          "phase" => "proposal",
          "directives" => ["Propose one concrete collaboration envelope and one publish path."]
        },
        "turn" => %{
          "round" => 1,
          "participant_role" => "architect",
          "objective" => "Produce the first proposal."
        },
        "shared" => %{
          "entries" => [],
          "instruction_log" => [],
          "tool_call_log" => []
        }
      }
    }
  end
end
