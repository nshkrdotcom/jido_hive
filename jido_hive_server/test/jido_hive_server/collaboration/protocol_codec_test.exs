defmodule JidoHiveServer.Collaboration.ProtocolCodecTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.ProtocolCodec

  test "normalizes relay hello payloads and injects workspace_id" do
    payload = %{
      participant_id: "participant-1",
      participant_role: "analyst",
      user_id: "user-1",
      client_version: "0.1.0"
    }

    assert {:ok, {:relay_hello, hello}} =
             ProtocolCodec.decode_inbound("relay.hello", payload, "workspace-1")

    assert hello["workspace_id"] == "workspace-1"
    assert hello["participant_id"] == "participant-1"
  end

  test "normalizes participant upsert payloads with nested runtime envelopes" do
    payload = %{
      "participant" => %{
        "target_id" => "target-1",
        "participant_id" => "participant-1",
        "participant_role" => "analyst",
        "capability_id" => "workspace.exec.session",
        "provider" => "codex",
        "execution_surface" => %{"transport" => "cli"},
        "execution_environment" => %{"workspace_root" => "/workspace"},
        "provider_options" => %{"model" => "gpt-5.4"}
      }
    }

    assert {:ok, {:participant_upsert, participant}} =
             ProtocolCodec.decode_inbound("participant.upsert", payload, "workspace-1")

    assert participant["workspace_id"] == "workspace-1"
    assert get_in(participant, ["execution_environment", "workspace_root"]) == "/workspace"
  end

  test "normalizes contribution submit payloads with nested contribution payloads" do
    payload = %{
      "contribution" => %{
        "room_id" => "room-1",
        "assignment_id" => "asn-1",
        "participant_id" => "participant-1",
        "participant_role" => "analyst",
        "contribution_type" => "reasoning",
        "authority_level" => "advisory",
        "summary" => "completed",
        "context_objects" => [],
        "execution" => %{"status" => "completed"}
      }
    }

    assert {:ok, {:contribution_submit, contribution}} =
             ProtocolCodec.decode_inbound("contribution.submit", payload, "workspace-1")

    assert contribution["room_id"] == "room-1"
    assert contribution["execution"]["status"] == "completed"
  end

  test "rejects malformed contribution payloads" do
    payload = %{"contribution" => %{"room_id" => "room-1"}}

    assert {:error, {:missing_field, "participant_id"}} =
             ProtocolCodec.decode_inbound("contribution.submit", payload, "workspace-1")
  end

  test "preserves nil relation target ids in contribution payloads" do
    payload = %{
      "contribution" => %{
        "room_id" => "room-1",
        "assignment_id" => "asn-1",
        "participant_id" => "participant-1",
        "participant_role" => "analyst",
        "contribution_type" => "reasoning",
        "authority_level" => "advisory",
        "summary" => "completed",
        "context_objects" => [
          %{
            "object_type" => "note",
            "title" => "Missing target",
            "relations" => [%{"relation" => "derives_from", "target_id" => nil}]
          }
        ],
        "execution" => %{"status" => "completed"}
      }
    }

    assert {:ok, {:contribution_submit, contribution}} =
             ProtocolCodec.decode_inbound("contribution.submit", payload, "workspace-1")

    assert get_in(contribution, [
             "context_objects",
             Access.at(0),
             "relations",
             Access.at(0),
             "target_id"
           ]) ==
             nil
  end

  test "encodes outbound assignment.start payloads with schema_version and string keys" do
    assignment = %{
      assignment_id: "asn-1",
      room_id: "room-1",
      participant_id: "participant-1",
      session: %{provider: :codex},
      contribution_contract: %{allowed_contribution_types: ["reasoning"]},
      context_view: %{brief: "Design a substrate."}
    }

    encoded = ProtocolCodec.encode_assignment_start(assignment)

    assert encoded["schema_version"] == "jido_hive/assignment.start.v1"
    assert encoded["assignment_id"] == "asn-1"
    assert encoded["session"]["provider"] == "codex"
  end
end
