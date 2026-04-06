defmodule JidoHiveServer.IntegrationsBootstrapTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2
  alias JidoHiveServer.IntegrationsBootstrap

  test "registers GitHub and Notion publication connectors with compatible direct targets" do
    :ok = IntegrationsBootstrap.bootstrap!()

    assert {:ok, github} = V2.fetch_connector("github")
    assert github.runtime_families == [:direct]
    assert {:ok, _capability} = V2.fetch_capability("github.issue.create")

    assert {:ok, github_targets} =
             V2.compatible_targets_for("github.issue.create", compatibility_requirements())

    assert Enum.any?(github_targets, fn match ->
             match.target.runtime_class == :direct
           end)

    assert {:ok, notion} = V2.fetch_connector("notion")
    assert notion.runtime_families == [:direct]
    assert {:ok, _capability} = V2.fetch_capability("notion.pages.create")

    assert {:ok, notion_targets} =
             V2.compatible_targets_for("notion.pages.create", compatibility_requirements())

    assert Enum.any?(notion_targets, fn match ->
             match.target.runtime_class == :direct
           end)
  end

  defp compatibility_requirements do
    %{
      version_requirement: "~> 1.0",
      accepted_runspec_versions: ["1.0.0"],
      accepted_event_schema_versions: ["1.0.0"]
    }
  end
end
