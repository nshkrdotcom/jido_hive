defmodule JidoHivePublications.PublicationWorkspaceTest do
  use ExUnit.Case, async: true

  alias JidoHivePublications.PublicationWorkspace

  test "builds a structured publication workspace from plan and auth state" do
    plan = %{
      "duplicate_policy" => "canonical_only",
      "source_entries" => ["ctx-1", "ctx-3"],
      "publications" => [
        %{
          "channel" => "github",
          "required_bindings" => [
            %{"field" => "repo", "description" => "Repository to publish into."}
          ],
          "draft" => %{
            "title" => "Fix Redis auth path",
            "body" => "Summary body"
          }
        }
      ]
    }

    auth_state = %{
      "github" => %{
        connection_id: "conn-1",
        source: :server,
        state: "connected",
        status: :cached
      }
    }

    workspace = PublicationWorkspace.build(plan, auth_state, selected_channel: "github")

    assert workspace.duplicate_policy == "canonical_only"
    assert workspace.source_entries == ["ctx-1", "ctx-3"]
    assert [%{channel: "github", selected?: true}] = workspace.channels
    assert workspace.selected_channel.channel == "github"
    assert workspace.selected_channel.auth.status == :cached
    assert workspace.preview_lines == ["Fix Redis auth path", "Summary body"]
  end

  test "reports readiness gaps when no channel is selected" do
    workspace = PublicationWorkspace.build(%{"publications" => []}, %{})

    assert workspace.channels == []
    assert workspace.ready? == false
    assert workspace.readiness == ["Select at least one publication channel."]
  end
end
