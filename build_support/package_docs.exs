defmodule JidoHive.Build.PackageDocs do
  @moduledoc false

  @source_url "https://github.com/nshkrdotcom/jido_hive"

  @spec docs(keyword()) :: keyword()
  def docs(opts) do
    package_title = Keyword.fetch!(opts, :package_title)
    root_prefix = Keyword.get(opts, :root_prefix, "..")

    [
      main: "readme",
      homepage_url: @source_url,
      source_ref: "main",
      source_url: @source_url,
      extras: extras(package_title, root_prefix),
      groups_for_extras: groups_for_extras(root_prefix)
    ]
  end

  defp extras(package_title, root_prefix) do
    [
      {"README.md", filename: "readme", title: "#{package_title} Overview"},
      {Path.join(root_prefix, "docs/architecture.md"),
       filename: "architecture", title: "Architecture"},
      {Path.join(root_prefix, "docs/debugging_guide.md"),
       filename: "debugging_guide", title: "Debugging Guide"},
      {Path.join(root_prefix, "setup/README.md"),
       filename: "setup_toolkit", title: "Setup Toolkit"},
      {Path.join(root_prefix, "docs/developer/multi_agent_round_robin.md"),
       filename: "multi_agent_round_robin", title: "Developer Guide: Multi-Agent Round Robin"},
      {Path.join(root_prefix, "LICENSE"), filename: "license", title: "License"}
    ]
  end

  defp groups_for_extras(root_prefix) do
    [
      Package: ["README.md"],
      "Project Overview": [Path.join(root_prefix, "LICENSE")],
      "User Guides": [
        Path.join(root_prefix, "docs/architecture.md"),
        Path.join(root_prefix, "docs/debugging_guide.md"),
        Path.join(root_prefix, "setup/README.md")
      ],
      "Developer Guides": [Path.join(root_prefix, "docs/developer/multi_agent_round_robin.md")]
    ]
  end
end
