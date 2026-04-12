defmodule JidoHiveWorkerRuntime.ProtocolCodecTest do
  use ExUnit.Case, async: true

  alias JidoHiveWorkerRuntime.Boundary.ProtocolCodec

  test "builds a canonical room join payload" do
    payload =
      ProtocolCodec.room_join_payload(
        %{
          workspace_id: "workspace-1",
          user_id: "user-1",
          participant_id: "participant-1",
          participant_role: "analyst",
          target_id: "target-1",
          capability_id: "capability-1",
          workspace_root: "/workspace",
          executor: {JidoHiveWorkerRuntime.Executor.Session, [provider: :codex]},
          runtime_id: :asm
        },
        12
      )

    assert get_in(payload, ["session", "mode"]) == "participant"
    assert get_in(payload, ["session", "last_seen_event_sequence"]) == 12
    assert get_in(payload, ["participant", "id"]) == "participant-1"
    assert get_in(payload, ["participant", "kind"]) == "agent"
    assert get_in(payload, ["participant", "meta", "role"]) == "analyst"
    assert get_in(payload, ["participant", "meta", "target_id"]) == "target-1"
    assert get_in(payload, ["participant", "meta", "workspace_root"]) == "/workspace"
  end

  test "normalizes a canonical assignment offer payload" do
    payload = %{
      "id" => "asn-1",
      "room_id" => "room-1",
      "participant_id" => "participant-1",
      "status" => "pending",
      "payload" => %{
        "objective" => "Design the refactor.",
        "phase" => "analysis",
        "context" => %{"brief" => "Refine the execution substrate.", "context_objects" => []},
        "prompt_config" => %{"system_prompt" => "Return JSON only."},
        "output_contract" => %{"allowed_contribution_types" => ["reasoning"]},
        "executor" => %{
          "provider" => "codex",
          "workspace_root" => "/workspace",
          "execution_environment" => %{"workspace_root" => "/workspace"}
        },
        "extension" => %{"source" => "worker-runtime-test"}
      },
      "meta" => %{
        "participant_meta" => %{
          "role" => "analyst",
          "target_id" => "target-1",
          "capability_id" => "capability-1"
        }
      }
    }

    assert {:ok, assignment} = ProtocolCodec.normalize_assignment_offer(payload)
    assert assignment["id"] == "asn-1"
    assert assignment["room_id"] == "room-1"
    assert assignment["objective"] == "Design the refactor."
    assert assignment["phase"] == "analysis"
    assert get_in(assignment, ["context", "brief"]) == "Refine the execution substrate."
    assert get_in(assignment, ["executor", "workspace_root"]) == "/workspace"
    assert get_in(assignment, ["output_contract", "allowed_contribution_types"]) == ["reasoning"]
    assert assignment["participant_role"] == "analyst"
    assert assignment["target_id"] == "target-1"
    assert assignment["capability_id"] == "capability-1"
  end

  test "normalizes an API data assignment offer envelope" do
    payload = %{
      "data" => %{
        "id" => "asn-2",
        "room_id" => "room-2",
        "participant_id" => "participant-2",
        "payload" => %{
          "objective" => "Refine the plan.",
          "context" => %{"brief" => "Focus on execution."},
          "executor" => %{"provider" => "codex"}
        }
      }
    }

    assert {:ok, assignment} = ProtocolCodec.normalize_assignment_offer(payload)
    assert assignment["id"] == "asn-2"
    assert assignment["objective"] == "Refine the plan."
    assert get_in(assignment, ["context", "brief"]) == "Focus on execution."
  end

  test "rejects a malformed canonical assignment payload" do
    payload = %{
      "id" => "asn-3",
      "room_id" => "room-3",
      "payload" => "not-a-map"
    }

    assert {:error, {:invalid_field, "payload"}} =
             ProtocolCodec.normalize_assignment_offer(payload)
  end

  test "normalizes contribution defaults into the canonical contribution resource" do
    contribution =
      ProtocolCodec.normalize_contribution(
        %{
          "summary" => "completed",
          "contribution_type" => "reasoning"
        },
        %{"id" => "asn-1", "room_id" => "room-1", "participant_id" => "participant-1"}
      )

    assert contribution["assignment_id"] == "asn-1"
    assert contribution["kind"] == "reasoning"
    assert get_in(contribution, ["payload", "summary"]) == "completed"
    assert get_in(contribution, ["payload", "context_objects"]) == nil
    assert get_in(contribution, ["meta", "status"]) == "completed"
  end

  test "preserves nil defaults and drops relations with missing targets" do
    contribution =
      ProtocolCodec.normalize_contribution(
        %{
          summary: "completed",
          kind: "reasoning",
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
        %{id: "asn-1", room_id: "room-1", target_id: nil}
      )

    assert contribution["target_id"] == nil

    assert [
             %{
               "object_type" => "note",
               "relations" => [%{"relation" => "derives_from", "target_id" => "ctx-1"}]
             }
           ] = get_in(contribution, ["payload", "context_objects"])
  end

  test "drops relation targets that are not visible in the assignment context" do
    contribution =
      ProtocolCodec.normalize_contribution(
        %{
          "summary" => "completed",
          "kind" => "reasoning",
          "context_objects" => [
            %{
              "object_type" => "belief",
              "title" => "Grounded note",
              "relations" => [
                %{"relation" => "references", "target_id" => "ctx-1"},
                %{"relation" => "derives_from", "target_id" => "brief-topic"}
              ]
            }
          ]
        },
        %{
          "id" => "asn-1",
          "room_id" => "room-1",
          "context" => %{
            "context_objects" => [
              %{"context_id" => "ctx-1"},
              %{"context_id" => "ctx-2"}
            ]
          }
        }
      )

    assert [
             %{
               "object_type" => "belief",
               "relations" => [%{"relation" => "references", "target_id" => "ctx-1"}]
             }
           ] = get_in(contribution, ["payload", "context_objects"])
  end
end
