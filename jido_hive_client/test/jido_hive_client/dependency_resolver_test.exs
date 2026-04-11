Code.require_file("../../build_support/dependency_resolver.exs", __DIR__)

defmodule JidoHiveClient.DependencyResolverTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Build.DependencyResolver

  test "prefers sibling repo paths for the runtime asm bridge in local workspace development" do
    assert {:jido_integration_v2_runtime_asm_bridge, opts} =
             DependencyResolver.jido_integration_runtime_asm_bridge()

    assert opts[:path] ==
             Path.expand("../../../../jido_integration/core/runtime_asm_bridge", __DIR__)
  end

  test "falls back to the live upstream main branch when workspace paths are absent" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "jido-hive-client-dependency-resolver-#{System.unique_integer()}"
      )

    File.mkdir_p!(tmp_dir)
    resolver_path = Path.join(tmp_dir, "dependency_resolver.exs")

    resolver_source =
      "../../build_support/dependency_resolver.exs"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> String.replace(
        "defmodule JidoHiveClient.Build.DependencyResolver do",
        "defmodule JidoHiveClient.Build.DependencyResolver.Isolated do"
      )

    File.write!(resolver_path, resolver_source)
    Code.require_file(resolver_path)

    isolated_resolver = JidoHiveClient.Build.DependencyResolver.Isolated

    assert {:jido_integration_v2_runtime_asm_bridge, opts} =
             isolated_resolver.jido_integration_runtime_asm_bridge()

    assert opts[:git] == "https://github.com/agentjido/jido_integration.git"
    assert opts[:branch] == "main"
    assert opts[:subdir] == "core/runtime_asm_bridge"
  end
end
