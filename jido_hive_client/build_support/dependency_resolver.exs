defmodule JidoHiveClient.Build.DependencyResolver do
  @moduledoc false

  @repo_root Path.expand("..", __DIR__)
  @jido_integration_repo "https://github.com/agentjido/jido_integration.git"

  def jido(opts \\ []), do: resolve_hex(:jido, "~> 2.2", [], opts)
  def jido_action(opts \\ []), do: resolve_hex(:jido_action, "~> 2.2", [], opts)

  def jido_signal(opts \\ []) do
    resolve(
      :jido_signal,
      ["../jido_signal", "../../jido_signal"],
      [github: "nshkrdotcom/jido_signal", branch: "main"],
      opts
    )
  end

  def jido_harness(opts \\ []) do
    resolve(
      :jido_harness,
      ["../jido_harness", "../../jido_harness"],
      [github: "nshkrdotcom/jido_harness", branch: "main"],
      opts
    )
  end

  def jido_shell(opts \\ []) do
    resolve(
      :jido_shell,
      ["../jido_shell", "../../jido_shell"],
      [github: "nshkrdotcom/jido_shell", branch: "main"],
      opts
    )
  end

  def jido_vfs(opts \\ []) do
    resolve(
      :jido_vfs,
      ["../jido_vfs", "../../jido_vfs"],
      [github: "nshkrdotcom/jido_vfs", branch: "main"],
      opts
    )
  end

  def sprites(opts \\ []) do
    resolve(:sprites, [], [github: "mikehostetler/sprites-ex", branch: "main"], opts)
  end

  def jido_integration_runtime_asm_bridge(opts \\ []) do
    resolve(
      :jido_integration_v2_runtime_asm_bridge,
      [
        "../jido_integration/core/runtime_asm_bridge",
        "../../jido_integration/core/runtime_asm_bridge"
      ],
      [
        git: @jido_integration_repo,
        branch: "main",
        subdir: "core/runtime_asm_bridge"
      ],
      opts
    )
  end

  defp resolve(app, local_paths, fallback_opts, opts) do
    case workspace_path(local_paths) do
      nil -> {app, Keyword.merge(fallback_opts, opts)}
      path -> {app, Keyword.merge([path: path], opts)}
    end
  end

  defp resolve_hex(app, requirement, local_paths, opts) do
    case workspace_path(local_paths) do
      nil -> {app, requirement, opts}
      path -> {app, Keyword.merge([path: path], opts)}
    end
  end

  defp workspace_path(local_paths) do
    if prefer_workspace_paths?() do
      Enum.find_value(local_paths, &existing_path/1)
    end
  end

  defp prefer_workspace_paths? do
    not Enum.member?(Path.split(@repo_root), "deps")
  end

  defp existing_path(relative_path) do
    expanded_path = Path.expand(relative_path, @repo_root)
    if File.dir?(expanded_path), do: expanded_path
  end
end
