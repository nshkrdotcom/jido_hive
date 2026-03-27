defmodule JidoHive.Build.DependencyResolver do
  @moduledoc false

  @repo_root Path.expand("..", __DIR__)

  def jido(opts \\ []) do
    resolve(
      :jido,
      ["../jido"],
      [github: "nshkrdotcom/jido", branch: "nshkrdotcom/phase-5-jido-surface-verification"],
      opts
    )
  end

  def jido_action(opts \\ []) do
    resolve(
      :jido_action,
      ["../jido_action"],
      [github: "nshkrdotcom/jido_action", branch: "main"],
      opts
    )
  end

  def jido_signal(opts \\ []) do
    resolve(
      :jido_signal,
      ["../jido_signal"],
      [github: "nshkrdotcom/jido_signal", branch: "main"],
      opts
    )
  end

  def jido_harness(opts \\ []) do
    resolve(
      :jido_harness,
      ["../jido_harness"],
      [github: "nshkrdotcom/jido_harness", branch: "main"],
      opts
    )
  end

  def jido_os(opts \\ []) do
    resolve(:jido_os, ["../jido_os"], [github: "epic-creative/jido_os", branch: "main"], opts)
  end

  def jido_shell(opts \\ []) do
    resolve(
      :jido_shell,
      ["../jido_shell"],
      [github: "nshkrdotcom/jido_shell", branch: "main"],
      opts
    )
  end

  def jido_vfs(opts \\ []) do
    resolve(
      :jido_vfs,
      ["../jido_vfs"],
      [github: "nshkrdotcom/jido_vfs", branch: "main"],
      opts
    )
  end

  def sprites(opts \\ []) do
    resolve(
      :sprites,
      ["../sprites-ex", "../sprites_ex"],
      [github: "mikehostetler/sprites-ex", branch: "main"],
      opts
    )
  end

  def jido_integration_platform(opts \\ []) do
    resolve(
      :jido_integration_v2,
      ["../jido_integration/core/platform"],
      [
        github: "agentjido/jido_integration",
        branch: "feat/universal-contract-standards",
        subdir: "core/platform"
      ],
      opts
    )
  end

  def jido_integration_runtime_asm_bridge(opts \\ []) do
    resolve(
      :jido_integration_v2_runtime_asm_bridge,
      ["../jido_integration/core/runtime_asm_bridge"],
      [
        github: "agentjido/jido_integration",
        branch: "feat/universal-contract-standards",
        subdir: "core/runtime_asm_bridge"
      ],
      opts
    )
  end

  def jido_integration_codex_cli(opts \\ []) do
    resolve(
      :jido_integration_v2_codex_cli,
      ["../jido_integration/connectors/codex_cli"],
      [
        github: "agentjido/jido_integration",
        branch: "feat/universal-contract-standards",
        subdir: "connectors/codex_cli"
      ],
      opts
    )
  end

  def jido_integration_github(opts \\ []) do
    resolve(
      :jido_integration_v2_github,
      ["../jido_integration/connectors/github"],
      [
        github: "agentjido/jido_integration",
        branch: "feat/universal-contract-standards",
        subdir: "connectors/github"
      ],
      opts
    )
  end

  def jido_integration_notion(opts \\ []) do
    resolve(
      :jido_integration_v2_notion,
      ["../jido_integration/connectors/notion"],
      [
        github: "agentjido/jido_integration",
        branch: "feat/universal-contract-standards",
        subdir: "connectors/notion"
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

    if File.dir?(expanded_path) do
      expanded_path
    end
  end
end
