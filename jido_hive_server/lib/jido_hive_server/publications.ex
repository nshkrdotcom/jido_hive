defmodule JidoHiveServer.Publications do
  @moduledoc false

  alias Jido.Integration.V2
  alias JidoHiveContextGraph.ContextDeduper
  alias JidoHiveServer.Persistence

  defmodule Gateway do
    @moduledoc false

    @callback invoke_publication(map(), map(), map()) :: {:ok, term()} | {:error, term()}
  end

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
      duplicate_policy: "canonical_only",
      source_entries: Enum.map(summary.source_context_objects, & &1.context_id),
      publications: Enum.map(@publication_specs, &publication_plan(&1, snapshot, summary))
    }
  end

  def compatibility_requirements, do: @compatibility_requirements

  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(snapshot, attrs) when is_map(snapshot) and is_map(attrs) do
    plan = build_plan(snapshot)

    runs =
      plan.publications
      |> selected_channels(attrs)
      |> Enum.map(&execute_publication(&1, snapshot, attrs))

    {:ok, %{room_id: snapshot.room_id, runs: runs}}
  end

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

  defp execute_publication(plan, snapshot, attrs) do
    channel = plan.channel || plan["channel"]
    connection_id = connection_id(attrs, channel)
    bindings = bindings(attrs, channel)
    publication_run_id = unique_id("publication")
    input = build_input(channel, plan, bindings)

    {:ok, _queued} =
      Persistence.create_publication_run(%{
        publication_run_id: publication_run_id,
        room_id: snapshot.room_id,
        channel: channel,
        connector_id: plan.connector_id,
        capability_id: plan.capability_id,
        status: "queued",
        request: %{
          "draft" => plan.draft,
          "input" => input,
          "connection_id" => connection_id,
          "bindings" => bindings
        }
      })

    result =
      case gateway().invoke_publication(plan, input, %{
             connection_id: connection_id,
             actor_id: attrs["actor_id"] || attrs[:actor_id],
             tenant_id: attrs["tenant_id"] || attrs[:tenant_id],
             notion_client: attrs["notion_client"] || attrs[:notion_client]
           }) do
        {:ok, invocation} ->
          {:ok,
           %{
             "run" => normalize(invocation.run),
             "output" => normalize(invocation.output)
           }}

        {:error, error} ->
          {:error, normalize(error)}
      end

    persist_publication_result(publication_run_id, result)
  end

  defp persist_publication_result(publication_run_id, {:ok, result}) do
    {:ok, persisted} =
      Persistence.update_publication_run(publication_run_id, %{
        status: "completed",
        result: result,
        error: %{}
      })

    persisted
  end

  defp persist_publication_result(publication_run_id, {:error, error}) do
    {:ok, persisted} =
      Persistence.update_publication_run(publication_run_id, %{
        status: "failed",
        result: %{},
        error: error
      })

    persisted
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

  defp selected_channels(publications, attrs) do
    requested =
      attrs["channels"] || attrs[:channels] ||
        Enum.filter(publications, & &1.requested) |> Enum.map(& &1.channel)

    Enum.filter(publications, &(&1.channel in requested))
  end

  defp connection_id(attrs, channel) do
    attrs
    |> Map.get("connections", Map.get(attrs, :connections, %{}))
    |> Map.get(channel)
  end

  defp bindings(attrs, channel) do
    attrs
    |> Map.get("bindings", Map.get(attrs, :bindings, %{}))
    |> Map.get(channel, %{})
  end

  defp build_input("github", plan, bindings) do
    %{
      repo: Map.get(bindings, "repo") || Map.get(bindings, :repo),
      title: plan.draft.title,
      body: plan.draft.body
    }
  end

  defp build_input("notion", plan, bindings) do
    title_property =
      Map.get(bindings, "title_property") || Map.get(bindings, :title_property) || "Name"

    data_source_id =
      Map.get(bindings, "parent.data_source_id") ||
        get_in(bindings, ["parent", "data_source_id"]) ||
        get_in(bindings, [:parent, :data_source_id])

    %{
      parent: %{"data_source_id" => data_source_id},
      properties: %{
        title_property => %{
          "title" => [%{"text" => %{"content" => plan.draft.title}}]
        }
      },
      children: plan.draft.children
    }
  end

  defp build_input(_channel, plan, _bindings), do: plan.draft

  defp summarize_room(snapshot) do
    source_context_objects = ContextDeduper.canonical_context_objects(snapshot)

    %{
      source_context_objects: source_context_objects,
      claims: objects_by_type(source_context_objects, ["belief", "claim", "decision"]),
      evidence: objects_by_type(source_context_objects, ["evidence", "artifact"]),
      objections: objects_by_type(source_context_objects, ["question", "constraint"]),
      publish_requests: publish_requests(snapshot)
    }
  end

  defp objects_by_type(entries, types) do
    Enum.filter(entries, &(&1.object_type in types))
  end

  defp publish_requests(snapshot) do
    Enum.filter(snapshot.contributions, fn contribution ->
      contribution.contribution_type == "publish_request" or
        contribution.authority_level == "binding"
    end)
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
      markdown_context_list(summary.claims),
      "",
      "## Evidence",
      markdown_context_list(summary.evidence),
      "",
      "## Open Questions / Constraints",
      markdown_context_list(summary.objections),
      "",
      "## Binding Publication Signals",
      markdown_contribution_list(summary.publish_requests)
    ]
    |> Enum.join("\n")
    |> String.trim()
  end

  defp markdown_list([]), do: "- None recorded."

  defp markdown_list(items) do
    items
    |> Enum.map_join("\n", fn item -> "- #{item}" end)
  end

  defp markdown_context_list([]), do: "- None recorded."

  defp markdown_context_list(entries) do
    entries
    |> Enum.map_join("\n", fn entry ->
      "- #{entry.object_type}: #{entry_line(entry)}"
    end)
  end

  defp markdown_contribution_list([]), do: "- None recorded."

  defp markdown_contribution_list(contributions) do
    contributions
    |> Enum.map_join("\n", fn contribution ->
      "- #{contribution.participant_role}: #{contribution.summary}"
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
      heading_block("Open Questions / Constraints"),
      bulleted_list_block(Enum.map(summary.objections, &entry_line/1)),
      heading_block("Binding Publication Signals"),
      bulleted_list_block(Enum.map(summary.publish_requests, & &1.summary))
    ]
    |> List.flatten()
  end

  defp entry_line(entry) do
    [entry.title, entry.body]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(": ")
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

  defp gateway do
    Application.get_env(
      :jido_hive_server,
      :publication_gateway,
      JidoHiveServer.Publications.IntegrationGateway
    )
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp normalize(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize()
  end

  defp normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {normalize_key(key), normalize(value)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(nil), do: nil
  defp normalize(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key
end
