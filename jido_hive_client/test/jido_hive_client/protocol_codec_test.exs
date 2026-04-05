defmodule JidoHiveClient.ProtocolCodecTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Boundary.ProtocolCodec

  test "normalizes a legacy job.start payload" do
    payload = %{
      job_id: "job-1",
      room_id: "room-1",
      participant_id: "participant-1",
      participant_role: "architect",
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
      collaboration_envelope: %{
        turn: %{phase: "proposal", objective: "Design the refactor."}
      }
    }

    assert {:ok, job} = ProtocolCodec.normalize_job_start(payload)
    assert job["job_id"] == "job-1"
    assert job["room_id"] == "room-1"

    assert get_in(job, ["session", "execution_surface", "transport_options", "timeout_ms"]) ==
             30_000

    assert get_in(job, ["session", "execution_environment", "workspace_root"]) == "/workspace"
    assert get_in(job, ["session", "provider_options", "model"]) == "gpt-5.4"
    assert get_in(job, ["collaboration_envelope", "turn", "phase"]) == "proposal"
  end

  test "normalizes a v2 job.start payload with a nested job envelope" do
    payload = %{
      "schema_version" => "jido_hive/job_start.v2",
      "job" => %{
        "job_id" => "job-2",
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
        "collaboration_envelope" => %{"turn" => %{"phase" => "critique"}}
      }
    }

    assert {:ok, job} = ProtocolCodec.normalize_job_start(payload)
    assert job["job_id"] == "job-2"
    assert job["room_id"] == "room-2"
    assert get_in(job, ["session", "execution_surface", "transport"]) == "cli"
    assert get_in(job, ["collaboration_envelope", "turn", "phase"]) == "critique"
  end

  test "rejects a malformed session envelope" do
    payload = %{
      "job_id" => "job-3",
      "room_id" => "room-3",
      "session" => "not-a-map"
    }

    assert {:error, {:invalid_field, "session"}} = ProtocolCodec.normalize_job_start(payload)
  end
end
