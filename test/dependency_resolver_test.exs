Code.require_file("../build_support/dependency_resolver.exs", __DIR__)

defmodule JidoHive.Build.DependencyResolverTest do
  use ExUnit.Case, async: true

  test "uses GitHub fallbacks when workspace paths are absent" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "jido-hive-dependency-resolver-#{System.unique_integer()}")

    build_support_dir = Path.join(tmp_dir, "build_support")
    File.mkdir_p!(build_support_dir)
    resolver_path = Path.join(build_support_dir, "dependency_resolver.exs")

    resolver_source =
      "/home/home/p/g/n/jido_hive/build_support/dependency_resolver.exs"
      |> File.read!()
      |> String.replace(
        "defmodule JidoHive.Build.DependencyResolver do",
        "defmodule JidoHive.Build.DependencyResolver.Isolated do"
      )

    File.write!(resolver_path, resolver_source)

    File.cp!(
      "/home/home/p/g/n/jido_hive/build_support/dependency_sources.exs",
      Path.join(build_support_dir, "dependency_sources.exs")
    )

    File.cp!(
      "/home/home/p/g/n/jido_hive/build_support/dependency_sources.config.exs",
      Path.join(build_support_dir, "dependency_sources.config.exs")
    )

    Code.require_file(resolver_path)

    isolated_resolver = JidoHive.Build.DependencyResolver.Isolated

    assert {:jido_ai, ai_opts} = apply(isolated_resolver, :jido_ai, [])
    assert ai_opts[:github] == "agentjido/jido_ai"
    assert ai_opts[:branch] == "main"

    assert {:jido_integration_v2, integration_opts} =
             apply(isolated_resolver, :jido_integration_platform, [])

    assert integration_opts[:github] == "agentjido/jido_integration"
    assert integration_opts[:subdir] == "core/platform"
    assert integration_opts[:branch] == "main"

    assert {:execution_plane, execution_plane_opts} =
             apply(isolated_resolver, :execution_plane, [])

    assert execution_plane_opts[:github] == "nshkrdotcom/execution_plane"
    assert execution_plane_opts[:subdir] == "core/execution_plane"
    assert execution_plane_opts[:branch] == "main"
    assert execution_plane_opts[:override] == true

    assert {:ground_plane_persistence_policy, ground_plane_opts} =
             apply(isolated_resolver, :ground_plane_persistence_policy, [])

    assert ground_plane_opts[:github] == "nshkrdotcom/ground_plane"
    assert ground_plane_opts[:subdir] == "core/persistence_policy"
    assert ground_plane_opts[:branch] == "main"
    assert ground_plane_opts[:override] == true

    assert {:jido_integration_contracts, contracts_opts} =
             apply(isolated_resolver, :jido_integration_contracts, [])

    assert contracts_opts[:github] == "agentjido/jido_integration"
    assert contracts_opts[:subdir] == "core/contracts"
    assert contracts_opts[:branch] == "main"

    assert {:jido_harness, harness_opts} = apply(isolated_resolver, :jido_harness, [])
    assert harness_opts[:github] == "nshkrdotcom/jido_harness"
    assert harness_opts[:branch] == "main"

    assert {:jido_integration_v2_asm_runtime_bridge, asm_bridge_opts} =
             apply(isolated_resolver, :jido_integration_asm_runtime_bridge, [])

    assert asm_bridge_opts[:github] == "agentjido/jido_integration"
    assert asm_bridge_opts[:subdir] == "core/asm_runtime_bridge"
    assert asm_bridge_opts[:branch] == "main"

    assert {:jido_hive_skill_contracts, skill_contract_opts} =
             apply(isolated_resolver, :jido_hive_skill_contracts, [])

    assert skill_contract_opts[:github] == "nshkrdotcom/jido_hive"
    assert skill_contract_opts[:subdir] == "core/skill_contracts"
    assert skill_contract_opts[:branch] == "main"

    assert {:jido_hive_skill_engine, skill_engine_opts} =
             apply(isolated_resolver, :jido_hive_skill_engine, [])

    assert skill_engine_opts[:github] == "nshkrdotcom/jido_hive"
    assert skill_engine_opts[:subdir] == "core/skill_engine"
    assert skill_engine_opts[:branch] == "main"

    assert {:jido_hive_skill_conformance_contracts, skill_conformance_opts} =
             apply(isolated_resolver, :jido_hive_skill_conformance_contracts, [])

    assert skill_conformance_opts[:github] == "nshkrdotcom/jido_hive"

    assert skill_conformance_opts[:subdir] ==
             "conformance_contracts/skill_conformance_contracts"

    assert skill_conformance_opts[:branch] == "main"

    for {function, app, subdir} <- [
          {:jido_hive_agent_coordinator, :jido_hive_agent_coordinator, "core/agent_coordinator"},
          {:jido_hive_inter_agent_messaging, :jido_hive_inter_agent_messaging,
           "core/inter_agent_messaging"},
          {:jido_hive_shared_memory_facade, :jido_hive_shared_memory_facade,
           "core/shared_memory_facade"},
          {:jido_hive_coordination_patterns, :jido_hive_coordination_patterns,
           "core/coordination_patterns"}
        ] do
      assert {^app, opts} = apply(isolated_resolver, function, [])
      assert opts[:github] == "nshkrdotcom/jido_hive"
      assert opts[:subdir] == subdir
      assert opts[:branch] == "main"
    end
  end
end
