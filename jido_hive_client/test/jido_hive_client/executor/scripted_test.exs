defmodule JidoHiveClient.Executor.ScriptedTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Executor.Scripted

  test "architect role emits structured collaboration actions and tool events" do
    job = %{
      "job_id" => "job-architect-1",
      "participant_id" => "architect",
      "participant_role" => "architect",
      "capability_id" => "codex.exec.session",
      "prompt_packet" => %{
        "brief" => "Design the collaboration protocol for a distributed idea room.",
        "context_summary" => "No prior context.",
        "rules" => ["Every objection must target a prior claim."],
        "shared_instruction_log" => [
          %{"role" => "operator", "body" => "Think in protocol shapes, not chat UI."}
        ]
      }
    }

    assert {:ok, result} = Scripted.run(job, role: :architect)
    assert result["job_id"] == "job-architect-1"
    assert result["participant_role"] == "architect"
    assert [%{"op" => "CLAIM"}, %{"op" => "EVIDENCE"} | _] = result["actions"]
    assert [%{"tool_name" => "context.read"} | _] = result["tool_events"]
    assert is_binary(result["summary"])
    assert result["summary"] =~ "architect"
  end
end
