defmodule JidoHiveClient.CollaborationPromptTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.CollaborationPrompt

  test "collaboration turns default to no tools and reinforce strict json output" do
    request = CollaborationPrompt.to_run_request(sample_job())

    assert request.allowed_tools == []

    assert request.system_prompt =~
             "Return exactly one JSON object that starts with { and ends with }."

    assert request.system_prompt =~
             "Allowed action ops for this turn: CLAIM, EVIDENCE, OBJECT, REVISE, DECIDE, PUBLISH"

    assert request.prompt =~ "Return the JSON object only."
  end

  test "explicit allowed tools still pass through when requested" do
    request = CollaborationPrompt.to_run_request(sample_job(), allowed_tools: ["shell.command"])

    assert request.allowed_tools == ["shell.command"]
  end

  defp sample_job do
    %{
      "job_id" => "job-client-1",
      "room_id" => "room-client-1",
      "participant_id" => "architect",
      "participant_role" => "architect",
      "session" => %{
        "workspace_root" => "/tmp/jido-hive-client-test",
        "provider" => "codex"
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
          "objective" => "Produce the first proposal.",
          "response_contract" => %{
            "allowed_ops" => ["CLAIM", "EVIDENCE", "OBJECT", "REVISE", "DECIDE", "PUBLISH"]
          }
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
