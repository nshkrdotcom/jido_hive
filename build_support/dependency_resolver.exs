defmodule JidoHive.Build.DependencyResolver do
  @moduledoc false

  @repo_root Path.expand("..", __DIR__)

  @jido_ref "99764b2ef76bde3b023848f1cacaac1ebb8ffa9c"
  @jido_action_ref "c320b2bb204bc3547eca3b10d7c09ddc97a6263a"
  @jido_signal_ref "94399473cf351fd66b6586af52114016a4ab31f2"
  @jido_harness_ref "70768e73681e2c34d15ddfa6dcb84343987524ea"
  @jido_os_ref "69034c84d9e593a4045241bd2095d7b66f0be1c8"
  @jido_integration_ref "5e11be43fe0964edc473849140cbe00a35dd48b7"

  def jido(opts \\ []) do
    resolve(:jido, ["../jido"], [github: "nshkrdotcom/jido", ref: @jido_ref], opts)
  end

  def jido_action(opts \\ []) do
    resolve(
      :jido_action,
      ["../jido_action"],
      [github: "nshkrdotcom/jido_action", ref: @jido_action_ref],
      opts
    )
  end

  def jido_signal(opts \\ []) do
    resolve(
      :jido_signal,
      ["../jido_signal"],
      [github: "nshkrdotcom/jido_signal", ref: @jido_signal_ref],
      opts
    )
  end

  def jido_harness(opts \\ []) do
    resolve(
      :jido_harness,
      ["../jido_harness"],
      [github: "nshkrdotcom/jido_harness", ref: @jido_harness_ref],
      opts
    )
  end

  def jido_os(opts \\ []) do
    resolve(:jido_os, ["../jido_os"], [github: "epic-creative/jido_os", ref: @jido_os_ref], opts)
  end

  def jido_integration_platform(opts \\ []) do
    resolve(
      :jido_integration_v2,
      ["../jido_integration/core/platform"],
      [github: "agentjido/jido_integration", ref: @jido_integration_ref, subdir: "core/platform"],
      opts
    )
  end

  def jido_integration_runtime_asm_bridge(opts \\ []) do
    resolve(
      :jido_integration_v2_runtime_asm_bridge,
      ["../jido_integration/core/runtime_asm_bridge"],
      [
        github: "agentjido/jido_integration",
        ref: @jido_integration_ref,
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
        ref: @jido_integration_ref,
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
        ref: @jido_integration_ref,
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
        ref: @jido_integration_ref,
        subdir: "connectors/notion"
      ],
      opts
    )
  end

  defp resolve(app, local_paths, fallback_opts, opts) do
    case Enum.find_value(local_paths, &existing_path/1) do
      nil -> {app, Keyword.merge(fallback_opts, opts)}
      path -> {app, Keyword.merge([path: path], opts)}
    end
  end

  defp existing_path(relative_path) do
    expanded_path = Path.expand(relative_path, @repo_root)

    if File.dir?(expanded_path) do
      expanded_path
    end
  end
end
