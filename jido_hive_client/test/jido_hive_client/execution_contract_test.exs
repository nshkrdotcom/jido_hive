defmodule JidoHiveClient.ExecutionContractTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.ExecutionContract

  test "target_registration_payload/2 emits the nested execution envelope without losing shorthands" do
    payload =
      ExecutionContract.target_registration_payload(
        [
          provider: :codex,
          model: "gpt-5.4",
          reasoning_effort: :low,
          cli_path: "/usr/local/bin/codex",
          execution_surface: [
            surface_kind: :ssh_exec,
            transport_options: [destination: "builder.example", port: 2222],
            target_id: "target-buildbox-1"
          ],
          execution_environment: [
            workspace_root: "/workspace",
            allowed_tools: ["git.status"],
            approval_posture: :manual,
            permission_mode: :default
          ]
        ],
        "/workspace"
      )

    assert payload["provider"] == "codex"
    assert payload["workspace_root"] == "/workspace"
    assert payload["execution_surface"]["surface_kind"] == "ssh_exec"
    assert payload["execution_surface"]["transport_options"]["destination"] == "builder.example"
    assert payload["execution_environment"]["workspace_root"] == "/workspace"
    assert payload["execution_environment"]["allowed_tools"] == ["git.status"]
    assert payload["execution_environment"]["approval_posture"] == "manual"
    assert payload["execution_environment"]["permission_mode"] == "default"
    assert payload["provider_options"]["model"] == "gpt-5.4"
    assert payload["provider_options"]["reasoning_effort"] == "low"
    assert payload["provider_options"]["cli_path"] == "/usr/local/bin/codex"
  end

  test "apply_session_defaults/2 and start_session_opts/4 preserve nested contracts for ASM" do
    job = %{
      "job_id" => "job-1",
      "room_id" => "room-1",
      "participant_id" => "architect",
      "session" => %{
        "provider" => "codex",
        "execution_surface" => %{
          "surface_kind" => "ssh_exec",
          "transport_options" => %{"destination" => "builder.example"}
        },
        "execution_environment" => %{
          "workspace_root" => "/workspace",
          "allowed_tools" => ["git.status"],
          "approval_posture" => "manual",
          "permission_mode" => "default"
        },
        "provider_options" => %{
          "model" => "gpt-5.4",
          "reasoning_effort" => "low",
          "cli_path" => "/usr/local/bin/codex"
        }
      }
    }

    defaults = ExecutionContract.apply_session_defaults(job, [])

    assert defaults[:provider] == :codex
    assert defaults[:model] == "gpt-5.4"
    assert defaults[:reasoning_effort] == :low
    assert defaults[:cli_path] == "/usr/local/bin/codex"
    assert defaults[:execution_surface]["surface_kind"] == "ssh_exec"
    assert defaults[:execution_environment]["workspace_root"] == "/workspace"
    assert ExecutionContract.workspace_root(job, defaults) == "/workspace"
    assert ExecutionContract.allowed_tools(job, defaults) == ["git.status"]

    start_opts = ExecutionContract.start_session_opts(job, defaults, :codex, "session-room-1")

    assert start_opts[:provider] == :codex
    assert start_opts[:session_id] == "session-room-1"
    assert start_opts[:cwd] == "/workspace"
    assert start_opts[:cli_path] == "/usr/local/bin/codex"
    assert start_opts[:execution_surface]["surface_kind"] == "ssh_exec"
    assert start_opts[:execution_environment]["workspace_root"] == "/workspace"
    assert start_opts[:execution_environment]["allowed_tools"] == ["git.status"]
  end
end
