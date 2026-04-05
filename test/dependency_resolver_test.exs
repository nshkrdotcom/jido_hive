Code.require_file("../build_support/dependency_resolver.exs", __DIR__)

defmodule JidoHive.Build.DependencyResolverTest do
  use ExUnit.Case, async: true

  test "uses git fallbacks for full-url repository deps when workspace paths are absent" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "jido-hive-dependency-resolver-#{System.unique_integer()}")

    File.mkdir_p!(tmp_dir)
    resolver_path = Path.join(tmp_dir, "dependency_resolver.exs")

    resolver_source =
      "/home/home/p/g/n/jido_hive/build_support/dependency_resolver.exs"
      |> File.read!()
      |> String.replace(
        "defmodule JidoHive.Build.DependencyResolver do",
        "defmodule JidoHive.Build.DependencyResolver.Isolated do"
      )

    File.write!(resolver_path, resolver_source)
    Code.require_file(resolver_path)

    isolated_resolver = JidoHive.Build.DependencyResolver.Isolated

    assert {:jido_ai, ai_opts} = apply(isolated_resolver, :jido_ai, [])
    assert ai_opts[:git] == "https://github.com/agentjido/jido_ai.git"
    assert ai_opts[:branch] == "main"

    assert {:jido_integration_v2, integration_opts} =
             apply(isolated_resolver, :jido_integration_platform, [])

    assert integration_opts[:git] == "https://github.com/agentjido/jido_integration.git"
    assert integration_opts[:subdir] == "core/platform"

    assert {:jido_vfs, vfs_opts} = apply(isolated_resolver, :jido_vfs, [])
    assert vfs_opts[:github] == "nshkrdotcom/jido_vfs"
    assert vfs_opts[:branch] == "main"
  end
end
