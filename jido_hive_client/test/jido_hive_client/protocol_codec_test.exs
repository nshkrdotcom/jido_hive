defmodule JidoHiveClient.ProtocolCodecTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Boundary.ProtocolCodec

  test "normalizes an assignment.start payload" do
    payload = %{
      assignment_id: "asn-1",
      room_id: "room-1",
      participant_id: "participant-1",
      participant_role: "analyst",
      target_id: "target-1",
      capability_id: "capability-1",
      session: %{
        provider: "codex",
        execution_surface: %{
          transport: "cli",
          transport_options: %{timeout_ms: 30_000}
        },
        execution_environment: %{
          workspace_root: "/workspace",
          allowed_tools: ["git.status"]
        },
        provider_options: %{
          model: "gpt-5.4",
          reasoning_effort: "low"
        }
      },
      contribution_contract: %{
        allowed_contribution_types: ["reasoning"],
        allowed_object_types: ["belief"],
        allowed_relation_types: ["derives_from"]
      },
      context_view: %{
        brief: "Design the refactor.",
        context_objects: []
      }
    }

    assert {:ok, assignment} = ProtocolCodec.normalize_assignment_start(payload)
    assert assignment["assignment_id"] == "asn-1"
    assert assignment["room_id"] == "room-1"

    assert get_in(assignment, ["session", "execution_surface", "transport_options", "timeout_ms"]) ==
             30_000

    assert get_in(assignment, ["session", "execution_environment", "workspace_root"]) ==
             "/workspace"

    assert get_in(assignment, ["session", "provider_options", "model"]) == "gpt-5.4"
  end

  test "normalizes a nested assignment.start envelope" do
    payload = %{
      "schema_version" => "jido_hive/assignment.start.v1",
      "assignment" => %{
        "assignment_id" => "asn-2",
        "room_id" => "room-2",
        "participant_id" => "participant-2",
        "participant_role" => "skeptic",
        "target_id" => "target-2",
        "capability_id" => "capability-2",
        "session" => %{
          "provider" => "codex",
          "execution_surface" => %{"transport" => "cli"},
          "execution_environment" => %{"workspace_root" => "/workspace-2"}
        },
        "contribution_contract" => %{"allowed_contribution_types" => ["reasoning"]},
        "context_view" => %{"brief" => "Refine the plan.", "context_objects" => []}
      }
    }

    assert {:ok, assignment} = ProtocolCodec.normalize_assignment_start(payload)
    assert assignment["assignment_id"] == "asn-2"
    assert get_in(assignment, ["session", "execution_surface", "transport"]) == "cli"
  end

  test "rejects a malformed session envelope" do
    payload = %{
      "assignment_id" => "asn-3",
      "room_id" => "room-3",
      "session" => "not-a-map"
    }

    assert {:error, {:invalid_field, "session"}} =
             ProtocolCodec.normalize_assignment_start(payload)
  end

  test "normalizes contribution defaults" do
    contribution =
      ProtocolCodec.normalize_contribution(
        %{
          "summary" => "completed",
          "contribution_type" => "reasoning",
          "authority_level" => "advisory"
        },
        %{"assignment_id" => "asn-1", "room_id" => "room-1"}
      )

    assert contribution["schema_version"] == "jido_hive/contribution.submit.v1"
    assert contribution["assignment_id"] == "asn-1"
    assert contribution["context_objects"] == []
  end

  test "preserves nil defaults and drops relations with missing targets" do
    contribution =
      ProtocolCodec.normalize_contribution(
        %{
          summary: "completed",
          contribution_type: "reasoning",
          context_objects: [
            %{
              object_type: "note",
              title: "Forward-compatible provenance design",
              relations: [
                %{relation: "references", target_id: nil},
                %{relation: "derives_from", target_id: "ctx-1"},
                %{relation: "references", target_id: " "}
              ]
            }
          ]
        },
        %{assignment_id: "asn-1", room_id: "room-1", target_id: nil}
      )

    assert contribution["target_id"] == nil

    assert [
             %{
               "object_type" => "note",
               "relations" => [%{"relation" => "derives_from", "target_id" => "ctx-1"}]
             }
           ] = contribution["context_objects"]
  end
end
