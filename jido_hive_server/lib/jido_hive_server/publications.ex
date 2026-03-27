defmodule JidoHiveServer.Publications do
  @moduledoc false

  alias Jido.Integration.V2

  @compatibility_requirements %{
    version_requirement: "~> 1.0",
    accepted_runspec_versions: ["1.0.0"],
    accepted_event_schema_versions: ["1.0.0"]
  }

  @publication_specs [
    %{
      channel: "github",
      capability_id: "github.issue.create",
      connector_id: "github",
      required_bindings: [
        %{
          field: "repo",
          source: "operator_input",
          description: "GitHub owner/repo destination for the room review issue."
        }
      ]
    },
    %{
      channel: "notion",
      capability_id: "notion.pages.create",
      connector_id: "notion",
      required_bindings: [
        %{
          field: "parent.data_source_id",
          source: "operator_input",
          description: "Notion parent data source that should receive the review page."
        },
        %{
          field: "title_property",
          source: "operator_input",
          description: "Title property name for the target Notion data source."
        }
      ]
    }
  ]

  def build_plan(snapshot) when is_map(snapshot) do
    summary = summarize_room(snapshot)

    %{
      room_id: snapshot.room_id,
      requested: summary.publish_requests != [],
      source_entries: Enum.map(snapshot.context_entries, & &1.entry_ref),
      publications: Enum.map(@publication_specs, &publication_plan(&1, snapshot, summary))
    }
  end

  def compatibility_requirements, do: @compatibility_requirements

  defp publication_plan(spec, snapshot, summary) do
    %{
      channel: spec.channel,
      connector_id: spec.connector_id,
      capability_id: spec.capability_id,
      compatible_targets: compatible_targets(spec.capability_id),
      required_bindings: spec.required_bindings,
      requested: summary.publish_requests != [],
      draft: draft(spec.channel, snapshot, summary)
    }
  end

  defp compatible_targets(capability_id) do
    case V2.compatible_targets_for(capability_id, @compatibility_requirements) do
      {:ok, matches} ->
        Enum.map(matches, fn match ->
          %{
            target_id: match.target.target_id,
            runtime_class: match.target.runtime_class,
            connector_id: match.connector.connector_id,
            connector_name: match.connector.display_name
          }
        end)

      {:error, _reason} ->
        []
    end
  end

  defp draft("github", snapshot, summary) do
    %{
      title: review_title(snapshot.brief),
      body: github_body(snapshot, summary)
    }
  end

  defp draft("notion", snapshot, summary) do
    %{
      title: review_title(snapshot.brief),
      children: notion_children(snapshot, summary)
    }
  end

  defp summarize_room(snapshot) do
    %{
      claims: entries_by_type(snapshot.context_entries, "claim"),
      evidence: entries_by_type(snapshot.context_entries, "evidence"),
      objections: entries_by_type(snapshot.context_entries, "objection"),
      publish_requests: entries_by_type(snapshot.context_entries, "publish_request")
    }
  end

  defp entries_by_type(entries, entry_type) do
    Enum.filter(entries, &(&1.entry_type == entry_type))
  end

  defp review_title(brief) do
    "Hive review: #{brief}"
  end

  defp github_body(snapshot, summary) do
    [
      "# #{review_title(snapshot.brief)}",
      "",
      "## Brief",
      snapshot.brief,
      "",
      "## Rules",
      markdown_list(snapshot.rules),
      "",
      "## Claims",
      markdown_entry_list(summary.claims),
      "",
      "## Evidence",
      markdown_entry_list(summary.evidence),
      "",
      "## Open Objections",
      markdown_entry_list(summary.objections),
      "",
      "## Publication Intent",
      markdown_entry_list(summary.publish_requests)
    ]
    |> Enum.join("\n")
    |> String.trim()
  end

  defp markdown_list([]), do: "- None recorded."

  defp markdown_list(items) do
    items
    |> Enum.map_join("\n", fn item -> "- #{item}" end)
  end

  defp markdown_entry_list([]), do: "- None recorded."

  defp markdown_entry_list(entries) do
    entries
    |> Enum.map_join("\n", fn entry ->
      "- #{entry.title}: #{entry.body}"
    end)
  end

  defp notion_children(snapshot, summary) do
    [
      paragraph_block(snapshot.brief),
      heading_block("Rules"),
      bulleted_list_block(Enum.map(snapshot.rules, & &1)),
      heading_block("Claims"),
      bulleted_list_block(Enum.map(summary.claims, &entry_line/1)),
      heading_block("Evidence"),
      bulleted_list_block(Enum.map(summary.evidence, &entry_line/1)),
      heading_block("Open Objections"),
      bulleted_list_block(Enum.map(summary.objections, &entry_line/1)),
      heading_block("Publication Intent"),
      bulleted_list_block(Enum.map(summary.publish_requests, &entry_line/1))
    ]
    |> List.flatten()
  end

  defp entry_line(entry) do
    "#{entry.title}: #{entry.body}"
  end

  defp paragraph_block(content) do
    %{
      "object" => "block",
      "type" => "paragraph",
      "paragraph" => %{
        "rich_text" => [%{"type" => "text", "text" => %{"content" => content}}]
      }
    }
  end

  defp heading_block(content) do
    %{
      "object" => "block",
      "type" => "heading_2",
      "heading_2" => %{
        "rich_text" => [%{"type" => "text", "text" => %{"content" => content}}]
      }
    }
  end

  defp bulleted_list_block([]), do: [paragraph_block("None recorded.")]

  defp bulleted_list_block(items) do
    Enum.map(items, fn content ->
      %{
        "object" => "block",
        "type" => "bulleted_list_item",
        "bulleted_list_item" => %{
          "rich_text" => [%{"type" => "text", "text" => %{"content" => content}}]
        }
      }
    end)
  end
end
