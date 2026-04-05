defmodule JidoHiveClient.Executor.RepairPolicyTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Executor.RepairPolicy

  test "attempts a single repair pass by default" do
    assert RepairPolicy.attempt_repair?([], "not valid json")
    refute RepairPolicy.attempt_repair?([], "")
  end

  test "disables repair when configured" do
    refute RepairPolicy.attempt_repair?([repair_mode: :disabled], "not valid json")
  end

  test "builds repair request opts with workspace root and clamped timeout" do
    job = %{"session" => %{"workspace_root" => "/workspace"}}
    opts = RepairPolicy.request_opts(job, model: "gpt-5.4", timeout_ms: 120_000)

    assert opts[:cwd] == "/workspace"
    assert opts[:model] == "gpt-5.4"
    assert opts[:timeout_ms] == 30_000
  end
end
