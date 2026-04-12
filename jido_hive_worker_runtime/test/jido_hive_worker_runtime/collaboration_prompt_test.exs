defmodule JidoHiveWorkerRuntime.CollaborationPromptTest do
  use ExUnit.Case, async: true

  alias JidoHiveWorkerRuntime.CollaborationPrompt

  test "assignments default to no tools and reinforce strict json output" do
    request = CollaborationPrompt.to_run_request(sample_assignment())

    assert request.allowed_tools == []

    assert request.system_prompt =~
             "Return exactly one JSON object that starts with { and ends with }."

    assert request.system_prompt =~ "Allowed contribution types: reasoning, artifact"
    assert request.system_prompt =~ "\"kind\": \"reasoning|artifact\""
    assert request.system_prompt =~ "\"payload\": {"
    assert request.system_prompt =~ "\"summary\": \"string\""

    assert request.system_prompt =~
             "Do not return wrapper keys like schema_version, room_id, participant_id"

    assert request.system_prompt =~
             "Do not return legacy top-level keys like summary, context_objects, artifacts, or authority_level."

    assert request.prompt =~ "Return the JSON object only."
    assert request.prompt =~ "Assignment packet JSON:"
    assert request.prompt =~ "\"allowed_contribution_types\""
    assert request.prompt =~ "\"reasoning\""

    assert request.system_prompt =~
             "Valid relation target ids from visible room context: ctx-root-1"

    assert request.system_prompt =~ "Never invent ids"
  end

  test "explicit allowed tools still pass through when requested" do
    request =
      CollaborationPrompt.to_run_request(sample_assignment(), allowed_tools: ["shell.command"])

    assert request.allowed_tools == ["shell.command"]
  end

  defp sample_assignment do
    %{
      "id" => "asn-client-1",
      "room_id" => "room-client-1",
      "participant_id" => "analyst",
      "participant_role" => "analyst",
      "executor" => %{
        "workspace_root" => "/tmp/jido-hive-client-test",
        "provider" => "codex"
      },
      "output_contract" => %{
        "allowed_contribution_types" => ["reasoning", "artifact"],
        "allowed_object_types" => ["belief", "note", "question"],
        "allowed_relation_types" => ["derives_from", "references"]
      },
      "context" => %{
        "brief" => "Design a shared participation substrate.",
        "rules" => ["Return structured contributions only."],
        "context_objects" => [
          %{
            "context_id" => "ctx-root-1",
            "object_type" => "belief",
            "title" => "Existing context"
          }
        ]
      },
      "phase" => "analysis",
      "objective" => "Produce the first reasoning contribution."
    }
  end
end
