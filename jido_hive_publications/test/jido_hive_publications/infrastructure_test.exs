defmodule JidoHivePublications.InfrastructureTest do
  use ExUnit.Case, async: true

  alias JidoHivePublications.Infrastructure

  test "memory preflight is non-mutating by default" do
    assert :ok = Infrastructure.preflight([])
    assert :ok = Infrastructure.preflight(profile: :mickey_mouse)
    assert :ok = Infrastructure.preflight(profile: :memory_debug)
  end

  test "durable preflight fails before mutation when migration proof is missing" do
    assert {:error, {:missing_migration_proof, :jido_hive_publications}} =
             Infrastructure.preflight(profile: :integration_postgres)
  end

  test "durable preflight passes when migration proof is present" do
    assert :ok = Infrastructure.preflight(profile: :integration_postgres, migration_proof: true)
  end
end
