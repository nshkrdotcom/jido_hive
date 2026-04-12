defmodule JidoHivePublications.Service do
  @moduledoc false

  alias Jido.Integration.V2
  alias JidoHiveContextGraph.ContextDeduper
  alias JidoHivePublications.{PublicationChannelBinding, Storage}

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

  @spec build_plan(map()) :: map()
  def build_plan(snapshot) when is_map(snapshot) do
    summary = summarize_room(snapshot)

    %{
      room_id: room_id(snapshot),
      requested: summary.publish_requests != [],
      duplicate_policy: "canonical_only",
      source_entries: Enum.map(summary.source_context_objects, &context_id/1),
      publications: Enum.map(@publication_specs, &publication_plan(&1, snapshot, summary))
    }
  end

  @spec compatibility_requirements() :: map()
  def compatibility_requirements, do: @compatibility_requirements

  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(snapshot, attrs) when is_map(snapshot) and is_map(attrs) do
    plan = build_plan(snapshot)

    runs =
      plan.publications
      |> selected_channels(attrs)
      |> Enum.map(&execute_publication(&1, snapshot, attrs))

    {:ok, %{room_id: room_id(snapshot), runs: runs}}
  end

  defp publication_plan(spec, snapshot, summary) do
    %{
      channel: spec.channel,
      connector_id: spec.connector_id,
      capability_id: spec.capability_id,
      compatible_targets: compatible_targets(spec.capability_id),
      required_bindings:
        Enum.map(
          spec.required_bindings,
          &(spec.channel
            |> PublicationChannelBinding.new!(&1)
            |> PublicationChannelBinding.to_map())
        ),
      requested: summary.publish_requests != [],
      draft: draft(spec.channel, snapshot, summary)
    }
  end

  defp execute_publication(plan, snapshot, attrs) do
    channel = value(plan, "channel")
    connection_id = connection_id(attrs, channel)
    bindings = bindings(attrs, channel)
    publication_run_id = unique_id("publication")
    input = build_input(channel, plan, bindings)

    {:ok, _queued} =
      Storage.create_run(%{
        publication_run_id: publication_run_id,
        room_id: room_id(snapshot),
        channel: channel,
        connector_id: value(plan, "connector_id"),
        capability_id: value(plan, "capability_id"),
        status: "queued",
        request: %{
          "draft" => value(plan, "draft"),
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
      Storage.update_run(publication_run_id, %{
        status: "completed",
        result: result,
        error: %{}
      })

    persisted
  end

  defp persist_publication_result(publication_run_id, {:error, error}) do
    {:ok, persisted} =
      Storage.update_run(publication_run_id, %{
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
  catch
    :exit, _reason ->
      []
  end

  defp draft("github", snapshot, summary) do
    %{
      title: review_title(snapshot),
      body: github_body(snapshot, summary)
    }
  end

  defp draft("notion", snapshot, summary) do
    %{
      title: review_title(snapshot),
      children: notion_children(snapshot, summary)
    }
  end

  defp selected_channels(publications, attrs) do
    requested =
      attrs["channels"] || attrs[:channels] ||
        Enum.filter(publications, &value(&1, "requested")) |> Enum.map(&value(&1, "channel"))

    Enum.filter(publications, &(value(&1, "channel") in requested))
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
      title: get_in(plan, [:draft, :title]) || get_in(plan, ["draft", "title"]),
      body: get_in(plan, [:draft, :body]) || get_in(plan, ["draft", "body"])
    }
  end

  defp build_input("notion", plan, bindings) do
    title_property =
      Map.get(bindings, "title_property") || Map.get(bindings, :title_property) || "Name"

    data_source_id =
      Map.get(bindings, "parent.data_source_id") ||
        get_in(bindings, ["parent", "data_source_id"]) ||
        get_in(bindings, [:parent, :data_source_id])

    title = get_in(plan, [:draft, :title]) || get_in(plan, ["draft", "title"])
    children = get_in(plan, [:draft, :children]) || get_in(plan, ["draft", "children"]) || []

    %{
      parent: %{"data_source_id" => data_source_id},
      properties: %{
        title_property => %{
          "title" => [%{"text" => %{"content" => title}}]
        }
      },
      children: children
    }
  end

  defp build_input(_channel, plan, _bindings), do: value(plan, "draft")

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
    Enum.filter(entries, &(object_type(&1) in types))
  end

  defp publish_requests(snapshot) do
    snapshot
    |> contributions()
    |> Enum.filter(fn contribution ->
      contribution_type(contribution) == "publish_request" or
        authority_level(contribution) == "binding"
    end)
  end

  defp review_title(snapshot) do
    "Hive review: #{room_name(snapshot)}"
  end

  defp github_body(snapshot, summary) do
    [
      "# #{review_title(snapshot)}",
      "",
      "## Brief",
      room_name(snapshot),
      "",
      "## Rules",
      markdown_list(rules(snapshot)),
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
      "- #{object_type(entry)}: #{entry_line(entry)}"
    end)
  end

  defp markdown_contribution_list([]), do: "- None recorded."

  defp markdown_contribution_list(contributions) do
    contributions
    |> Enum.map_join("\n", fn contribution ->
      "- #{participant_role(contribution)}: #{contribution_summary(contribution)}"
    end)
  end

  defp notion_children(snapshot, summary) do
    [
      paragraph_block(room_name(snapshot)),
      heading_block("Rules"),
      bulleted_list_block(Enum.map(rules(snapshot), & &1)),
      heading_block("Claims"),
      bulleted_list_block(Enum.map(summary.claims, &entry_line/1)),
      heading_block("Evidence"),
      bulleted_list_block(Enum.map(summary.evidence, &entry_line/1)),
      heading_block("Open Questions / Constraints"),
      bulleted_list_block(Enum.map(summary.objections, &entry_line/1)),
      heading_block("Binding Publication Signals"),
      bulleted_list_block(Enum.map(summary.publish_requests, &contribution_summary/1))
    ]
    |> List.flatten()
  end

  defp paragraph_block(content) do
    %{
      "object" => "block",
      "type" => "paragraph",
      "paragraph" => %{"rich_text" => rich_text(content)}
    }
  end

  defp heading_block(content) do
    %{
      "object" => "block",
      "type" => "heading_2",
      "heading_2" => %{"rich_text" => rich_text(content)}
    }
  end

  defp bulleted_list_block([]), do: [paragraph_block("None recorded.")]

  defp bulleted_list_block(items) do
    Enum.map(items, fn item ->
      %{
        "object" => "block",
        "type" => "bulleted_list_item",
        "bulleted_list_item" => %{"rich_text" => rich_text(item)}
      }
    end)
  end

  defp rich_text(content) do
    [%{"type" => "text", "text" => %{"content" => content}}]
  end

  defp entry_line(entry) do
    title = value(entry, "title")
    body = value(entry, "body")

    [title, body]
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.join(": ")
  end

  defp contribution_summary(contribution) do
    value(contribution, "summary") || value(contribution, "body") || "[no summary]"
  end

  defp room_name(snapshot) do
    value(snapshot, "name") || value(snapshot, "brief") || "Untitled room"
  end

  defp room_id(snapshot) do
    value(snapshot, "room_id") || value(snapshot, "id")
  end

  defp rules(snapshot) do
    value(snapshot, "rules") ||
      get_in(snapshot, ["config", "rules"]) ||
      get_in(snapshot, [:config, :rules]) ||
      []
  end

  defp contributions(snapshot) do
    value(snapshot, "contributions") || []
  end

  defp object_type(entry) do
    value(entry, "object_type") || value(entry, "type") || "entry"
  end

  defp context_id(entry) do
    value(entry, "context_id") || value(entry, "id")
  end

  defp contribution_type(contribution) do
    value(contribution, "contribution_type") || value(contribution, "kind")
  end

  defp participant_role(contribution) do
    value(contribution, "participant_role") || "participant"
  end

  defp authority_level(contribution) do
    value(contribution, "authority_level") ||
      get_in(contribution, ["meta", "authority_level"]) ||
      get_in(contribution, [:meta, :authority_level])
  end

  defp gateway do
    Application.get_env(
      :jido_hive_publications,
      :publication_gateway,
      JidoHivePublications.IntegrationGateway
    )
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}"
  end

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(%_{} = value), do: value |> Map.from_struct() |> normalize()

  defp normalize(value) when is_map(value) do
    Map.new(value, fn {key, inner} -> {key, normalize(inner)} end)
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value), do: value
end
