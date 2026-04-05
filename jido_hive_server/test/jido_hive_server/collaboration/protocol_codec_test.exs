defmodule JidoHiveServer.Collaboration.ProtocolCodecTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.ProtocolCodec

  test "normalizes legacy relay hello payloads and injects workspace_id" do
    payload = %{
      participant_id: "participant-1",
      participant_role: "architect",
      user_id: "user-1",
      client_version: "0.1.0"
    }

    assert {:ok, {:relay_hello, hello}} =
             ProtocolCodec.decode_inbound("relay.hello", payload, "workspace-1")

    assert hello["workspace_id"] == "workspace-1"
    assert hello["participant_id"] == "participant-1"
    assert hello["participant_role"] == "architect"
  end

  test "normalizes v2 target registration payloads and preserves nested runtime envelopes" do
    payload = %{
      "schema_version" => "jido_hive/target.register.v2",
      "target" => %{
        "target_id" => "target-1",
        "capability_id" => "capability-1",
        "participant_id" => "participant-1",
        "participant_role" => "architect",
        "provider" => "codex",
        "execution_surface" => %{
          "transport" => "cli",
          "transport_options" => %{"tty" => true}
        },
        "execution_environment" => %{"workspace_root" => "/workspace"},
        "provider_options" => %{"model" => "gpt-5.4"}
      }
    }

    assert {:ok, {:target_register, target}} =
             ProtocolCodec.decode_inbound("target.register", payload, "workspace-1")

    assert target["workspace_id"] == "workspace-1"
    assert get_in(target, ["execution_surface", "transport_options", "tty"]) == true
    assert get_in(target, ["execution_environment", "workspace_root"]) == "/workspace"
    assert get_in(target, ["provider_options", "model"]) == "gpt-5.4"
  end

  test "normalizes v2 job results with nested result payloads" do
    payload = %{
      "schema_version" => "jido_hive/job.result.v2",
      "result" => %{
        "job_id" => "job-1",
        "room_id" => "room-1",
        "participant_id" => "participant-1",
        "participant_role" => "architect",
        "target_id" => "target-1",
        "status" => "completed",
        "summary" => "completed",
        "actions" => [],
        "tool_events" => [],
        "events" => [],
        "approvals" => [],
        "artifacts" => [],
        "execution" => %{"status" => "completed"}
      }
    }

    assert {:ok, {:job_result, result}} =
             ProtocolCodec.decode_inbound("job.result.v2", payload, "workspace-1")

    assert result["job_id"] == "job-1"
    assert result["room_id"] == "room-1"
    assert result["execution"]["status"] == "completed"
  end

  test "rejects malformed job result payloads" do
    payload = %{"result" => %{"job_id" => "job-1"}}

    assert {:error, {:missing_field, "room_id"}} =
             ProtocolCodec.decode_inbound("job.result.v2", payload, "workspace-1")
  end

  test "encodes outbound job.start payloads with schema_version and string keys" do
    job = %{
      job_id: "job-1",
      room_id: "room-1",
      participant_id: "participant-1",
      session: %{provider: :codex},
      collaboration_envelope: %{turn: %{phase: "proposal"}}
    }

    encoded = ProtocolCodec.encode_job_start(job)

    assert encoded["schema_version"] == "jido_hive/job.start.v2"
    assert encoded["job_id"] == "job-1"
    assert encoded["session"]["provider"] == "codex"
    assert encoded["collaboration_envelope"]["turn"]["phase"] == "proposal"
  end
end
