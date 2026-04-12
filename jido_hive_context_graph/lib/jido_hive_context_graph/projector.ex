defmodule JidoHiveContextGraph.Projector do
  @moduledoc false

  alias JidoHiveContextGraph.{
    ContextDeduper,
    ContextGraph,
    ContextManager,
    WorkflowSummary
  }

  alias JidoHiveContextGraph.Schema.ContextObject

  @spec project(map()) :: map()
  def project(snapshot) when is_map(snapshot) do
    explicit_summary = explicit_workflow_summary(snapshot)
    explicit_annotations = explicit_context_annotations(snapshot)

    snapshot
    |> materialize_context_objects()
    |> ensure_context_defaults()
    |> ContextGraph.attach()
    |> then(fn projected ->
      computed_annotations =
        projected
        |> ContextManager.rebuild_annotations()
        |> merge_annotations(ContextDeduper.rebuild_annotations(projected))

      annotations =
        explicit_annotations
        |> merge_annotations(computed_annotations)

      workflow_summary =
        if preserve_explicit_workflow_summary?(snapshot) do
          explicit_summary
        else
          WorkflowSummary.build(projected)
        end

      projected
      |> Map.put(:context_annotations, annotations)
      |> Map.put(:workflow_summary, workflow_summary)
    end)
  end

  defp materialize_context_objects(snapshot) do
    contributions =
      Map.get(snapshot, :contributions) ||
        Map.get(snapshot, "contributions", [])

    existing_context_objects = explicit_context_objects(snapshot)
    existing_by_contribution = existing_context_objects_by_contribution(existing_context_objects)

    {derived_context_objects, next_context_seq} =
      build_derived_context_objects(contributions, existing_by_contribution, 1)

    context_objects =
      existing_context_objects
      |> merge_context_objects(List.flatten(derived_context_objects))

    snapshot
    |> Map.put(:context_objects, context_objects)
    |> Map.put(:next_context_seq, next_context_seq)
    |> Map.put(:status, room_status(snapshot))
    |> Map.put(:context_config, context_config(snapshot))
  end

  defp build_derived_context_objects(contributions, existing_by_contribution, start_seq) do
    Enum.map_reduce(contributions, start_seq, fn contribution, seq ->
      existing_objects =
        Map.get(existing_by_contribution, contribution_id(contribution), [])

      contribution
      |> contribution_projection(existing_objects, seq)
      |> then(fn {objects, next_seq} -> {Enum.reject(objects, &is_nil/1), next_seq} end)
    end)
  end

  defp contribution_projection(contribution, existing_objects, seq) do
    contribution
    |> contribution_context_objects()
    |> Enum.with_index()
    |> Enum.map_reduce(seq, fn {draft, draft_index}, draft_seq ->
      build_context_object(contribution, draft, draft_index, draft_seq, existing_objects)
    end)
  end

  defp build_context_object(contribution, draft, draft_index, draft_seq, existing_objects) do
    existing_object = Enum.at(existing_objects, draft_index)

    attrs =
      context_object_attrs(
        contribution,
        draft,
        existing_context_id(existing_object) || "ctx-#{draft_seq}"
      )

    {context_object_from_draft(draft, attrs), next_context_seq(existing_object, draft_seq)}
  end

  defp context_object_from_draft(draft, attrs) do
    case ContextObject.from_draft(draft, attrs) do
      {:ok, built} -> Map.from_struct(built)
      {:error, _reason} -> nil
    end
  end

  defp next_context_seq(nil, draft_seq), do: draft_seq + 1

  defp next_context_seq(existing_object, draft_seq) do
    existing_object
    |> existing_context_id()
    |> next_context_seq_after()
    |> max(draft_seq)
  end

  defp ensure_context_defaults(snapshot) do
    snapshot
    |> Map.put_new(:context_config, %{participant_scopes: %{}})
    |> Map.put_new(:context_annotations, %{})
  end

  defp explicit_context_objects(snapshot) do
    case Map.get(snapshot, :context_objects) || Map.get(snapshot, "context_objects") do
      objects when is_list(objects) -> objects
      _other -> []
    end
  end

  defp explicit_context_annotations(snapshot) do
    snapshot
    |> Map.get(:context_annotations, Map.get(snapshot, "context_annotations", %{}))
    |> normalize_map()
  end

  defp explicit_workflow_summary(snapshot) do
    snapshot
    |> Map.get(:workflow_summary, Map.get(snapshot, "workflow_summary", %{}))
    |> normalize_map()
  end

  defp preserve_explicit_workflow_summary?(snapshot) do
    explicit_workflow_summary(snapshot) != %{} and
      contribution_list(snapshot) == []
  end

  defp contribution_context_objects(contribution) do
    payload = normalize_map(Map.get(contribution, :payload) || Map.get(contribution, "payload"))

    payload
    |> Map.get(:context_objects, Map.get(payload, "context_objects"))
    |> case do
      drafts when is_list(drafts) -> drafts
      _other -> []
    end
  end

  defp context_object_attrs(contribution, draft, context_id_or_seq) do
    payload = normalize_map(Map.get(contribution, :payload) || Map.get(contribution, "payload"))
    meta = normalize_map(Map.get(contribution, :meta) || Map.get(contribution, "meta"))

    %{
      context_id:
        Map.get(draft, :context_id) || Map.get(draft, "context_id") ||
          normalize_context_id(context_id_or_seq),
      authored_by: authored_by_attrs(contribution, meta),
      provenance: provenance_attrs(contribution, payload, meta),
      inserted_at: contribution_inserted_at(contribution)
    }
  end

  defp authored_by_attrs(contribution, meta) do
    %{
      participant_id: contribution_value(contribution, "participant_id"),
      participant_role: Map.get(meta, "participant_role") || Map.get(meta, :participant_role),
      target_id: Map.get(meta, "target_id") || Map.get(meta, :target_id),
      capability_id: Map.get(meta, "capability_id") || Map.get(meta, :capability_id)
    }
  end

  defp provenance_attrs(contribution, payload, meta) do
    %{
      contribution_id: contribution_id(contribution),
      assignment_id: contribution_value(contribution, "assignment_id"),
      consumed_context_ids:
        Map.get(payload, "consumed_context_ids") ||
          Map.get(payload, :consumed_context_ids, []),
      source_event_ids: Map.get(meta, "source_event_ids") || Map.get(meta, :source_event_ids, []),
      authority_level: Map.get(meta, "authority_level") || Map.get(meta, :authority_level),
      contribution_type: contribution_type(contribution, meta)
    }
  end

  defp contribution_type(contribution, _meta) do
    contribution_value(contribution, "kind")
  end

  defp contribution_inserted_at(contribution) do
    contribution_value(contribution, "inserted_at") ||
      contribution_value(contribution, "recorded_at") ||
      DateTime.utc_now()
  end

  defp room_status(snapshot) do
    Map.get(snapshot, :workflow_status) || Map.get(snapshot, "workflow_status") ||
      Map.get(snapshot, :status) || Map.get(snapshot, "status") || "waiting"
  end

  defp context_config(snapshot) do
    case Map.get(snapshot, :context_config) || Map.get(snapshot, "context_config") do
      %{} = context_config ->
        normalize_context_config(context_config)

      _other ->
        config = normalize_map(Map.get(snapshot, :config) || Map.get(snapshot, "config"))

        config
        |> Map.get("context_graph", Map.get(config, :context_graph, %{}))
        |> normalize_context_config()
    end
  end

  defp normalize_context_config(%{} = context_config) do
    participant_scopes =
      context_config
      |> Map.get(:participant_scopes, Map.get(context_config, "participant_scopes", %{}))
      |> Map.new(fn {participant_id, scope} ->
        {participant_id, normalize_scope(scope)}
      end)

    %{participant_scopes: participant_scopes}
  end

  defp normalize_context_config(_context_config), do: %{participant_scopes: %{}}

  defp normalize_scope(%{} = scope) do
    %{
      writable_types:
        normalize_dimension(Map.get(scope, :writable_types) || Map.get(scope, "writable_types")),
      writable_node_ids:
        normalize_dimension(
          Map.get(scope, :writable_node_ids) || Map.get(scope, "writable_node_ids")
        ),
      reference_hop_limit:
        Map.get(scope, :reference_hop_limit) || Map.get(scope, "reference_hop_limit") || 2
    }
  end

  defp normalize_scope(_scope) do
    %{
      writable_types: :all,
      writable_node_ids: :all,
      reference_hop_limit: 2
    }
  end

  defp normalize_dimension(:all), do: :all
  defp normalize_dimension("all"), do: :all

  defp normalize_dimension(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp normalize_dimension(_values), do: :all

  defp normalize_context_id(context_id) when is_binary(context_id), do: context_id
  defp normalize_context_id(seq) when is_integer(seq), do: "ctx-#{seq}"
  defp normalize_context_id(_other), do: "ctx-1"

  defp existing_context_objects_by_contribution(existing_context_objects) do
    existing_context_objects
    |> Enum.filter(&(provenance_contribution_id(&1) not in [nil, ""]))
    |> Enum.group_by(&provenance_contribution_id/1)
    |> Map.new(fn {contribution_id, objects} ->
      {contribution_id, Enum.sort_by(objects, &{inserted_at(&1), context_object_id(&1)})}
    end)
  end

  defp contribution_list(snapshot) do
    case Map.get(snapshot, :contributions) || Map.get(snapshot, "contributions") do
      contributions when is_list(contributions) -> contributions
      _other -> []
    end
  end

  defp merge_context_objects(existing_context_objects, derived_context_objects) do
    existing_index =
      Map.new(existing_context_objects, fn object -> {context_object_id(object), object} end)

    {ordered_ids, merged_index} =
      Enum.reduce(
        derived_context_objects,
        {Enum.map(existing_context_objects, &context_object_id/1), existing_index},
        fn object, {ids, index} ->
          context_id = context_object_id(object)

          next_ids =
            if context_id in ids do
              ids
            else
              ids ++ [context_id]
            end

          {next_ids, Map.put(index, context_id, object)}
        end
      )

    ordered_ids
    |> Enum.uniq()
    |> Enum.map(&Map.get(merged_index, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp context_object_id(%{} = object) do
    Map.get(object, :context_id) || Map.get(object, "context_id")
  end

  defp existing_context_id(nil), do: nil
  defp existing_context_id(object), do: context_object_id(object)

  defp provenance_contribution_id(%{} = object) do
    object
    |> Map.get(:provenance, Map.get(object, "provenance", %{}))
    |> contribution_id()
  end

  defp contribution_id(%{} = contribution) do
    contribution_value(contribution, "id")
  end

  defp inserted_at(%{} = object) do
    Map.get(object, :inserted_at) || Map.get(object, "inserted_at") ||
      ~U[1970-01-01 00:00:00Z]
  end

  defp next_context_seq_after("ctx-" <> suffix) do
    case Integer.parse(suffix) do
      {integer, ""} when integer >= 0 -> integer + 1
      _other -> 0
    end
  end

  defp next_context_seq_after(_context_id), do: 0

  defp merge_annotations(left, right) do
    Map.merge(left, right, fn _context_id, left_annotation, right_annotation ->
      Map.merge(left_annotation, right_annotation)
    end)
  end

  defp contribution_value(map, key) when is_map(map) do
    Map.get(map, key) ||
      Map.get(map, existing_atom_key(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_other), do: %{}
end
