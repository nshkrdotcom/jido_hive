defmodule JidoHiveClient.RoomInsight do
  @moduledoc """
  Shared operator-facing insight helpers derived from authoritative room truth.

  This module is intentionally transport-agnostic and reusable from both
  headless tooling and interactive clients.
  """

  alias JidoHiveClient.RoomWorkflow

  @type action_item :: %{label: String.t(), shortcut: String.t()}

  @spec control_plane(map()) :: map()
  def control_plane(snapshot) when is_map(snapshot) do
    summary = RoomWorkflow.summary(snapshot)

    %{
      objective: summary.objective,
      stage: summary.stage,
      next_action: summary.next_action,
      reason: control_plane_reason(summary),
      publish_ready: summary.publish_ready,
      publish_blockers: summary.publish_blockers,
      blockers: summary.blockers,
      graph_counts: compact_graph_counts(summary.graph_counts),
      focus_queue: build_focus_queue(snapshot, summary.focus_candidates)
    }
  end

  def control_plane(_snapshot) do
    control_plane(%{})
  end

  @spec provenance_trace(map(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def provenance_trace(snapshot, context_id) when is_map(snapshot) and is_binary(context_id) do
    objects = context_objects(snapshot)
    index = Map.new(objects, fn object -> {object_context_id(object), object} end)

    case Map.get(index, context_id) do
      nil ->
        {:error, :not_found}

      object ->
        {incoming, outgoing} = graph_edges(object, snapshot)

        {:ok,
         %{
           context_id: object_context_id(object),
           title: object_title(object),
           object_type: object_type(object),
           authority_level: provenance_authority(object) || "advisory",
           authored_by: authored_by(object),
           confidence: confidence(object),
           graph: %{incoming: length(incoming), outgoing: length(outgoing)},
           flags: %{
             binding: binding?(object),
             conflict: conflict?(object, snapshot),
             duplicate_count: duplicate_hidden_count(object),
             stale: stale?(object)
           },
           recommended_actions: recommended_actions(object, snapshot),
           trace: provenance_entries(object, index, 0, nil, %{})
         }}
    end
  end

  def provenance_trace(_snapshot, _context_id), do: {:error, :not_found}

  @spec recommended_actions(map(), map()) :: [action_item()]
  def recommended_actions(object, snapshot) when is_map(object) and is_map(snapshot) do
    actions =
      []
      |> maybe_prepend_action(conflict?(object, snapshot), %{
        label: "Open conflict resolution",
        shortcut: "Enter"
      })
      |> maybe_prepend_action(object_type(object) == "question", %{
        label: "Send clarification",
        shortcut: "Enter"
      })
      |> maybe_append_action(%{label: "Inspect provenance", shortcut: "Ctrl+E"})
      |> maybe_append_action(%{label: "Accept selected object", shortcut: "Ctrl+A"})
      |> maybe_append_action(
        if object_type(object) == "decision" and publish_ready?(snapshot) do
          %{label: "Review publication plan", shortcut: "Ctrl+P"}
        end
      )

    Enum.uniq(actions)
  end

  def recommended_actions(_object, _snapshot), do: []

  defp build_focus_queue(snapshot, focus_candidates) do
    index =
      Map.new(context_objects(snapshot), fn object -> {object_context_id(object), object} end)

    focus_candidates
    |> Kernel.++(inferred_focus_candidates(snapshot))
    |> Enum.map(&normalize_focus_candidate(&1, index))
    |> Enum.uniq_by(fn item -> {item.kind, item.context_id} end)
  end

  defp inferred_focus_candidates(snapshot) do
    snapshot
    |> context_objects()
    |> Enum.filter(&(duplicate_hidden_count(&1) > 0 and duplicate_status(&1) != "duplicate"))
    |> Enum.map(fn object ->
      %{
        kind: "duplicate_cluster",
        context_id: object_context_id(object),
        duplicate_count: duplicate_hidden_count(object)
      }
    end)
  end

  defp normalize_focus_candidate(focus_candidate, index) do
    candidate = normalize_map(focus_candidate)
    context_id = Map.get(candidate, :context_id) || Map.get(candidate, "context_id")
    kind = Map.get(candidate, :kind) || Map.get(candidate, "kind") || "focus"
    object = Map.get(index, context_id, %{})

    %{
      kind: to_string(kind),
      context_id: context_id,
      title: object_title(object),
      why: focus_reason(kind, candidate, object),
      action: focus_action(kind)
    }
  end

  defp control_plane_reason(%{publish_ready: true}),
    do: "Server reports the room is ready to publish."

  defp control_plane_reason(%{publish_blockers: [first | _rest]}) when is_binary(first), do: first

  defp control_plane_reason(%{blockers: blockers}) when is_list(blockers) and blockers != [] do
    blockers
    |> Enum.map(&normalize_map/1)
    |> Enum.map_join(" · ", fn blocker ->
      kind = Map.get(blocker, :kind) || Map.get(blocker, "kind") || "blocker"
      count = Map.get(blocker, :count) || Map.get(blocker, "count") || 1
      "#{count} #{humanize_kind(kind, count)}"
    end)
  end

  defp control_plane_reason(_summary), do: "No active blockers reported."

  defp compact_graph_counts(graph_counts) when is_map(graph_counts) do
    graph_counts
    |> normalize_map()
    |> Enum.reduce(%{}, fn
      {:total, value}, acc when is_integer(value) -> Map.put(acc, :total, value)
      {key, value}, acc when is_integer(value) and value > 0 -> Map.put(acc, key, value)
      {_key, _value}, acc -> acc
    end)
  end

  defp focus_reason("contradiction", _candidate, _object),
    do: "Contradiction requires operator arbitration"

  defp focus_reason("question", _candidate, _object), do: "Question is still blocking progress"

  defp focus_reason("duplicate_cluster", candidate, object) do
    count =
      Map.get(candidate, :duplicate_count) || Map.get(candidate, "duplicate_count") ||
        duplicate_hidden_count(object)

    "#{count} #{pluralize("duplicate is", "duplicates are", count)} collapsed under the canonical entry"
  end

  defp focus_reason(_kind, _candidate, _object), do: "Operator review recommended"

  defp focus_action("contradiction"), do: "Open conflict resolution"
  defp focus_action("question"), do: "Send clarification"

  defp focus_action("duplicate_cluster"),
    do: "Review the canonical entry before accepting or publishing"

  defp focus_action(_kind), do: "Inspect selected detail"

  defp provenance_entries(_object, _index, depth, _via, _visited) when depth > 5, do: []

  defp provenance_entries(object, index, depth, via, visited) do
    context_id = object_context_id(object)

    if Map.has_key?(visited, context_id) do
      [
        %{
          depth: depth,
          via: via,
          context_id: context_id,
          object_type: object_type(object),
          title: object_title(object),
          cycle: true
        }
      ]
    else
      next_visited = Map.put(visited, context_id, true)

      [
        %{
          depth: depth,
          via: via,
          context_id: context_id,
          object_type: object_type(object),
          title: object_title(object),
          cycle: false
        }
      ] ++
        provenance_children(object, index, depth, next_visited)
    end
  end

  defp provenance_children(object, index, depth, visited) do
    object
    |> relations()
    |> Enum.filter(&provenance_relation?/1)
    |> Enum.flat_map(fn relation ->
      relation_name = relation_value(relation)
      target_id = relation_target_id(relation)

      case Map.get(index, target_id) do
        nil ->
          [
            %{
              depth: depth + 1,
              via: relation_name,
              context_id: target_id,
              object_type: "missing",
              title: "[not in view]",
              cycle: false
            }
          ]

        child ->
          provenance_entries(child, index, depth + 1, relation_name, visited)
      end
    end)
  end

  defp provenance_relation?(relation) do
    relation_value(relation) in ["derives_from", "references", :derives_from, :references]
  end

  defp graph_edges(object, scope) do
    adjacency = Map.get(object, "adjacency") || Map.get(object, :adjacency) || %{}
    incoming = Map.get(adjacency, "incoming") || Map.get(adjacency, :incoming) || []
    outgoing = Map.get(adjacency, "outgoing") || Map.get(adjacency, :outgoing) || []

    if incoming == [] and outgoing == [] do
      object_id = object_context_id(object)
      objects = scope_context_objects(scope)
      derived_incoming = incoming_relations(objects, object_id)
      derived_outgoing = outgoing_relations(object)
      {derived_incoming, derived_outgoing}
    else
      {incoming, outgoing}
    end
  end

  defp incoming_relations(objects, object_id) do
    Enum.flat_map(objects, fn object ->
      object
      |> relations()
      |> Enum.filter(fn relation ->
        relation_target_id(relation) == object_id
      end)
      |> Enum.map(fn relation ->
        %{
          "type" => relation_value(relation),
          "from_id" => object_context_id(object),
          "target_id" => object_id
        }
      end)
    end)
  end

  defp outgoing_relations(object) do
    Enum.map(relations(object), fn relation ->
      %{
        "type" => relation_value(relation),
        "target_id" => relation_target_id(relation)
      }
    end)
  end

  defp conflict?(object, scope) do
    {incoming, outgoing} = graph_edges(object, scope)

    object_type(object) == "contradiction" or
      Enum.any?(incoming ++ outgoing, &contradiction_edge?/1)
  end

  defp contradiction_edge?(edge) do
    edge_type = Map.get(edge, "type") || Map.get(edge, :type)
    edge_relation = Map.get(edge, "relation") || Map.get(edge, :relation)
    edge_type in ["contradicts", :contradicts] or edge_relation in ["contradicts", :contradicts]
  end

  defp maybe_prepend_action(actions, true, action), do: [action | actions]
  defp maybe_prepend_action(actions, false, _action), do: actions
  defp maybe_append_action(actions, nil), do: actions
  defp maybe_append_action(actions, action), do: actions ++ [action]

  defp publish_ready?(snapshot) do
    Map.get(snapshot, "status") == "publication_ready" or
      Map.get(snapshot, :status) == "publication_ready"
  end

  defp stale?(object) do
    derived = Map.get(object, "derived") || Map.get(object, :derived) || %{}
    Map.get(derived, "stale_ancestor") || Map.get(derived, :stale_ancestor) || false
  end

  defp duplicate_hidden_count(object) do
    case duplicate_size(object) do
      size when size > 1 -> size - 1
      _other -> 0
    end
  end

  defp duplicate_size(object) do
    derived = Map.get(object, "derived") || Map.get(object, :derived) || %{}
    Map.get(derived, "duplicate_size") || Map.get(derived, :duplicate_size) || 0
  end

  defp duplicate_status(object) do
    derived = Map.get(object, "derived") || Map.get(object, :derived) || %{}
    Map.get(derived, "duplicate_status") || Map.get(derived, :duplicate_status)
  end

  defp binding?(object), do: provenance_authority(object) == "binding"

  defp authored_by(object) do
    authored =
      Map.get(object, "authored_by") || Map.get(object, :authored_by) ||
        Map.get(object, "provenance") || Map.get(object, :provenance) || %{}

    Map.get(authored, "participant_id") || Map.get(authored, :participant_id)
  end

  defp provenance_authority(object) do
    provenance = Map.get(object, "provenance") || Map.get(object, :provenance) || %{}
    Map.get(provenance, "authority_level") || Map.get(provenance, :authority_level)
  end

  defp confidence(object) do
    uncertainty = Map.get(object, "uncertainty") || Map.get(object, :uncertainty) || %{}
    Map.get(uncertainty, "confidence") || Map.get(uncertainty, :confidence)
  end

  defp object_title(object) do
    Map.get(object, "title") || Map.get(object, :title) || Map.get(object, "body") ||
      Map.get(object, :body) || "[untitled]"
  end

  defp object_type(object), do: Map.get(object, "object_type") || Map.get(object, :object_type)

  defp object_context_id(object),
    do: Map.get(object, "context_id") || Map.get(object, :context_id)

  defp relations(object) do
    Map.get(object, "relations") || Map.get(object, :relations) || []
  end

  defp relation_value(relation), do: Map.get(relation, "relation") || Map.get(relation, :relation)

  defp relation_target_id(relation),
    do: Map.get(relation, "target_id") || Map.get(relation, :target_id)

  defp context_objects(snapshot),
    do: Map.get(snapshot, "context_objects") || Map.get(snapshot, :context_objects) || []

  defp scope_context_objects(scope), do: context_objects(scope)

  defp normalize_map(values) when is_map(values) do
    Map.new(values, fn {key, value} ->
      {normalize_key(key), normalize_value(value)}
    end)
  end

  defp normalize_map(_values), do: %{}

  defp normalize_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    case existing_atom_key(key) do
      nil -> key
      atom_key -> atom_key
    end
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp humanize_kind(kind, count) do
    kind
    |> to_string()
    |> String.replace("_", " ")
    |> then(fn label ->
      if count == 1, do: label, else: label <> "s"
    end)
  end

  defp pluralize(singular, _plural, 1), do: singular
  defp pluralize(_singular, plural, _count), do: plural
end
