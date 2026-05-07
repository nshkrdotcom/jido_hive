defmodule JidoHiveServer.PersistencePreflightTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Persistence

  test "memory preflight is non-mutating by default" do
    assert :ok = Persistence.preflight([])
    assert :ok = Persistence.preflight(profile: :mickey_mouse)
    assert :ok = Persistence.preflight(profile: :memory_debug)
  end

  test "durable preflight fails before mutation when migration proof is missing" do
    assert {:error, {:missing_migration_proof, :jido_hive_server}} =
             Persistence.preflight(profile: :integration_postgres)
  end

  test "durable preflight passes when migration proof is present" do
    assert :ok = Persistence.preflight(profile: :integration_postgres, migration_proof: true)
  end
end
