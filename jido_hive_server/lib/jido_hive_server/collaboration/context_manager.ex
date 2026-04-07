defmodule JidoHiveServer.Collaboration.ContextManager do
  @moduledoc false

  alias JidoHiveServer.Collaboration.ContextGraph

  @default_scope %{
    writable_types: :all,
    writable_node_ids: :all,
    reference_hop_limit: 2
  }

  @read_governed_relation_types [
    :derives_from,
    :references,
    :contradicts,
    :resolves,
    :supports,
    :blocks
  ]

  @spec validate_append(map(), map(), map()) :: :ok | {:error, {:scope_violation, map()}}
  def validate_append(participant, write_intent, room)
      when is_map(participant) and is_map(write_intent) and is_map(room) do
    room = ContextGraph.attach(room)
    scope = participant_scope(room, participant)
    writable_ids = writable_context_ids(participant, room, scope)
    readable_ids = readable_context_ids(participant, room, scope)

    validate_object_types(write_intent, scope)
    |> continue_validation(fn -> validate_supersedes_targets(write_intent, writable_ids) end)
    |> continue_validation(fn -> validate_read_targets(write_intent, readable_ids) end)
  end

  def validate_append(_participant, _write_intent, _room),
    do: {:error, {:scope_violation, %{kind: :invalid_append}}}

  @spec build_view(map(), map(), map()) :: [map()]
  def build_view(participant, task_context, room)
      when is_map(participant) and is_map(task_context) and is_map(room) do
    room = ContextGraph.attach(room)
    scope = participant_scope(room, participant)
    readable_ids = readable_context_ids(participant, room, scope)
    objects_by_id = objects_by_id(room)

    seed_ids =
      task_context
      |> seed_ids_for_view(room, readable_ids)
      |> Enum.filter(&MapSet.member?(readable_ids, &1))
      |> Enum.uniq()

    traversed_objects =
      traverse_view(room, seed_ids, readable_ids, 2)
      |> Enum.map(&Map.get(objects_by_id, &1))
      |> Enum.reject(&is_nil/1)

    traversed_objects
    |> maybe_filter_human_view(room, participant)
    |> Enum.map(&put_derived_annotation(&1, room))
  end

  def build_view(_participant, _task_context, _room), do: []

  @spec after_append(map(), map(), [String.t()]) :: %{
          room_events: [map()],
          context_annotations: %{optional(String.t()) => map()}
        }
  def after_append(before_room, after_room, appended_context_ids)
      when is_map(before_room) and is_map(after_room) and is_list(appended_context_ids) do
    before_room = ContextGraph.attach(before_room)
    after_room = ContextGraph.attach(after_room)

    annotations = annotation_delta(after_room, appended_context_ids)

    %{
      room_events:
        contradiction_events(before_room, after_room, appended_context_ids) ++
          downstream_invalidation_events(after_room, appended_context_ids),
      context_annotations: annotations
    }
  end

  def after_append(_before_room, _after_room, _appended_context_ids),
    do: %{room_events: [], context_annotations: %{}}

  @spec rebuild_annotations(map()) :: %{optional(String.t()) => map()}
  def rebuild_annotations(room) when is_map(room) do
    room = ContextGraph.attach(room)

    room
    |> context_objects()
    |> Enum.reduce(%{}, fn object, acc ->
      room
      |> stale_annotations_for_object(object)
      |> Enum.reduce(acc, fn {invalidated_id, superseded_ids}, annotations ->
        merge_annotation(annotations, invalidated_id, superseded_ids)
      end)
    end)
  end

  def rebuild_annotations(_room), do: %{}

  @spec readable_context_ids(map(), map()) :: MapSet.t(String.t())
  def readable_context_ids(participant, room) when is_map(participant) and is_map(room) do
    readable_context_ids(participant, room, participant_scope(room, participant))
  end

  def readable_context_ids(_participant, _room), do: MapSet.new()

  defp participant_scope(room, participant) do
    participant_id = participant_id(participant)

    room
    |> Map.get(:context_config, %{})
    |> Map.get(:participant_scopes, %{})
    |> Map.get(participant_id, @default_scope)
    |> normalize_scope()
  end

  defp normalize_scope(%{} = scope) do
    %{
      writable_types:
        normalize_scope_dimension(
          Map.get(scope, :writable_types) || Map.get(scope, "writable_types")
        ),
      writable_node_ids:
        normalize_scope_dimension(
          Map.get(scope, :writable_node_ids) || Map.get(scope, "writable_node_ids")
        ),
      reference_hop_limit:
        scope
        |> Map.get(:reference_hop_limit, Map.get(scope, "reference_hop_limit", 2))
        |> normalize_hop_limit()
    }
  end

  defp normalize_scope(_scope), do: @default_scope

  defp normalize_scope_dimension(:all), do: :all
  defp normalize_scope_dimension("all"), do: :all

  defp normalize_scope_dimension(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp normalize_scope_dimension(_values), do: :all

  defp normalize_hop_limit(value) when is_integer(value) and value >= 0, do: value
  defp normalize_hop_limit(_value), do: 2

  defp validate_object_types(write_intent, scope) do
    drafted_object_types =
      Map.get(
        write_intent,
        :drafted_object_types,
        Map.get(write_intent, "drafted_object_types", [])
      )

    Enum.find_value(drafted_object_types, :ok, fn object_type ->
      if type_writable?(scope, object_type) do
        nil
      else
        {:error, {:scope_violation, %{kind: :drafted_object_type, object_type: object_type}}}
      end
    end)
  end

  defp validate_supersedes_targets(write_intent, writable_ids) do
    write_intent
    |> relation_targets(:supersedes)
    |> Enum.find_value(:ok, fn target_id ->
      if MapSet.member?(writable_ids, target_id) do
        nil
      else
        {:error, {:scope_violation, %{kind: :supersedes_target, target_id: target_id}}}
      end
    end)
  end

  defp validate_read_targets(write_intent, readable_ids) do
    @read_governed_relation_types
    |> Enum.flat_map(fn relation_type ->
      Enum.map(relation_targets(write_intent, relation_type), &{relation_type, &1})
    end)
    |> Enum.find_value(:ok, fn {relation_type, target_id} ->
      if MapSet.member?(readable_ids, target_id) do
        nil
      else
        {:error,
         {:scope_violation,
          %{kind: :relation_target, relation_type: relation_type, target_id: target_id}}}
      end
    end)
  end

  defp relation_targets(write_intent, relation_type) do
    write_intent
    |> Map.get(:relation_targets_by_type, Map.get(write_intent, "relation_targets_by_type", %{}))
    |> Map.get(relation_type, [])
  end

  defp type_writable?(%{writable_types: :all}, _object_type), do: true

  defp type_writable?(%{writable_types: writable_types}, object_type),
    do: object_type in writable_types

  defp writable_context_ids(participant, room, scope) do
    room
    |> base_scope_ids(scope)
    |> Enum.filter(fn context_id ->
      ContextGraph.fetch_context_object(room, context_id)
      |> visible_to_participant?(participant)
    end)
    |> MapSet.new()
  end

  defp readable_context_ids(participant, room, scope) do
    roots =
      room
      |> base_scope_ids(scope)
      |> Enum.filter(fn context_id ->
        ContextGraph.fetch_context_object(room, context_id)
        |> visible_to_participant?(participant)
      end)
      |> Enum.sort()

    do_expand_references(
      room,
      participant,
      Enum.map(roots, &{&1, 0}),
      scope.reference_hop_limit,
      MapSet.new(roots)
    )
  end

  defp base_scope_ids(room, %{writable_node_ids: :all, writable_types: :all}) do
    Enum.map(context_objects(room), &object_id/1)
  end

  defp base_scope_ids(room, scope) do
    context_objects(room)
    |> Enum.filter(fn object ->
      object_id_writable?(scope, object_id(object)) or type_writable?(scope, object_type(object))
    end)
    |> Enum.map(&object_id/1)
  end

  defp object_id_writable?(%{writable_node_ids: :all}, _context_id), do: true

  defp object_id_writable?(%{writable_node_ids: writable_node_ids}, context_id),
    do: context_id in writable_node_ids

  defp do_expand_references(_room, _participant, [], _hop_limit, readable_ids), do: readable_ids

  defp do_expand_references(room, participant, queue, hop_limit, readable_ids) do
    {next_queue, next_readable_ids} =
      Enum.reduce(queue, {[], readable_ids}, fn {context_id, depth}, acc ->
        if depth >= hop_limit do
          acc
        else
          expand_reference_targets(room, participant, context_id, depth, acc)
        end
      end)

    next_queue =
      next_queue
      |> Enum.reverse()

    if next_queue == [] do
      next_readable_ids
    else
      do_expand_references(room, participant, next_queue, hop_limit, next_readable_ids)
    end
  end

  defp seed_ids_for_view(task_context, room, readable_ids) do
    anchor_context_id =
      Map.get(task_context, :anchor_context_id, Map.get(task_context, "anchor_context_id"))

    mode = Map.get(task_context, :mode, Map.get(task_context, "mode", :assignment))

    cond do
      is_binary(anchor_context_id) and MapSet.member?(readable_ids, anchor_context_id) ->
        [anchor_context_id]

      mode in [:human_pane, "human_pane"] ->
        room
        |> ContextGraph.derivation_roots()
        |> Enum.map(&object_id/1)
        |> Enum.filter(&MapSet.member?(readable_ids, &1))

      true ->
        []
    end
  end

  defp traverse_view(room, seed_ids, readable_ids, max_depth) do
    seed_ids
    |> Enum.map(&{&1, 0})
    |> do_traverse_view(room, readable_ids, max_depth, MapSet.new(seed_ids), seed_ids)
  end

  defp do_traverse_view([], _room, _readable_ids, _max_depth, _visited, acc), do: acc

  defp do_traverse_view(
         [{_context_id, depth} | rest],
         room,
         readable_ids,
         max_depth,
         visited,
         acc
       )
       when depth >= max_depth do
    do_traverse_view(rest, room, readable_ids, max_depth, visited, acc)
  end

  defp do_traverse_view([{context_id, depth} | rest], room, readable_ids, max_depth, visited, acc) do
    {neighbors, next_visited} =
      room
      |> ContextGraph.neighbors(context_id)
      |> Enum.reduce({[], visited}, fn object, {selected, seen} ->
        neighbor_id = object_id(object)

        cond do
          not MapSet.member?(readable_ids, neighbor_id) ->
            {selected, seen}

          MapSet.member?(seen, neighbor_id) ->
            {selected, seen}

          true ->
            {[neighbor_id | selected], MapSet.put(seen, neighbor_id)}
        end
      end)

    neighbors = Enum.reverse(neighbors)

    do_traverse_view(
      rest ++ Enum.map(neighbors, &{&1, depth + 1}),
      room,
      readable_ids,
      max_depth,
      next_visited,
      acc ++ neighbors
    )
  end

  defp maybe_filter_human_view(objects, room, participant) do
    if human_participant?(participant) do
      contradiction_ids =
        room
        |> ContextGraph.contradictions()
        |> Enum.flat_map(&[&1.from_id, &1.to_id])
        |> MapSet.new()

      open_question_ids =
        room
        |> ContextGraph.open_questions()
        |> Enum.map(&object_id/1)
        |> MapSet.new()

      visible_ids = MapSet.union(contradiction_ids, open_question_ids)

      Enum.filter(objects, &MapSet.member?(visible_ids, object_id(&1)))
    else
      objects
    end
  end

  defp contradiction_events(before_room, after_room, appended_context_ids) do
    before_keys =
      before_room
      |> ContextGraph.contradictions()
      |> MapSet.new(&contradiction_key/1)

    after_room
    |> ContextGraph.contradictions()
    |> Enum.reject(&MapSet.member?(before_keys, contradiction_key(&1)))
    |> Enum.map(fn edge ->
      left = ContextGraph.fetch_context_object(after_room, edge.from_id)
      right = ContextGraph.fetch_context_object(after_room, edge.to_id)

      %{
        type: :contradiction_detected,
        payload: %{
          left_context_id: edge.from_id,
          right_context_id: edge.to_id,
          left_object_type: object_type(left),
          right_object_type: object_type(right),
          heterogeneity_class: classify_heterogeneity(after_room, left, right),
          detected_from_context_ids:
            appended_context_ids
            |> Enum.filter(&(&1 in [edge.from_id, edge.to_id]))
            |> Enum.uniq()
        }
      }
    end)
  end

  defp downstream_invalidation_events(after_room, appended_context_ids) do
    objects_by_id = objects_by_id(after_room)

    appended_context_ids
    |> Enum.map(&Map.get(objects_by_id, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(fn object ->
      superseded_context_ids =
        after_room
        |> ContextGraph.adjacency(object_id(object))
        |> Map.get(:outgoing, [])
        |> Enum.filter(&(&1.type == :supersedes))
        |> Enum.map(& &1.to_id)
        |> Enum.uniq()

      invalidated_context_ids =
        superseded_context_ids
        |> Enum.flat_map(&downstream_derives_from_ids(after_room, &1))
        |> Enum.uniq()
        |> Enum.sort()

      if invalidated_context_ids == [] do
        []
      else
        [
          %{
            type: :downstream_invalidated,
            payload: %{
              source_context_id: object_id(object),
              superseded_context_ids: superseded_context_ids,
              invalidated_context_ids: invalidated_context_ids,
              reason: :supersedes
            }
          }
        ]
      end
    end)
  end

  defp annotation_delta(after_room, appended_context_ids) do
    full_annotations = rebuild_annotations(after_room)

    after_room
    |> downstream_invalidation_events(appended_context_ids)
    |> Enum.flat_map(fn event ->
      Map.get(event.payload, :invalidated_context_ids, [])
    end)
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn context_id, acc ->
      case Map.get(full_annotations, context_id) do
        nil -> acc
        annotation -> Map.put(acc, context_id, annotation)
      end
    end)
  end

  defp classify_heterogeneity(room, left, right) do
    left_authority = authority_level(left)
    right_authority = authority_level(right)

    cond do
      left_authority != right_authority and "binding" in [left_authority, right_authority] ->
        :authority

      shared_provenance_root?(room, left, right) and capability_id(left) != capability_id(right) ->
        :capability

      disjoint_knowledge_inputs?(room, left, right) ->
        :knowledge

      shared_upstream_context?(room, left, right) ->
        :epistemic

      true ->
        :unknown
    end
  end

  defp shared_provenance_root?(room, left, right) do
    left_roots = provenance_roots(room, left)
    right_roots = provenance_roots(room, right)
    sets_intersect?(left_roots, right_roots)
  end

  defp disjoint_knowledge_inputs?(room, left, right) do
    left_roots = provenance_roots(room, left)
    right_roots = provenance_roots(room, right)

    left_consumed = consumed_context_ids(left)
    right_consumed = consumed_context_ids(right)

    sets_disjoint?(left_roots, right_roots) or sets_disjoint?(left_consumed, right_consumed)
  end

  defp shared_upstream_context?(room, left, right) do
    left_upstream =
      room
      |> ContextGraph.provenance_chain(object_id(left))
      |> Enum.map(&object_id/1)
      |> Enum.uniq()

    right_upstream =
      room
      |> ContextGraph.provenance_chain(object_id(right))
      |> Enum.map(&object_id/1)
      |> Enum.uniq()

    sets_intersect?(left_upstream, right_upstream) or
      sets_intersect?(consumed_context_ids(left), consumed_context_ids(right))
  end

  defp provenance_roots(_room, nil), do: []

  defp provenance_roots(room, object) do
    object_id = object_id(object)

    room
    |> ContextGraph.provenance_chain(object_id)
    |> Enum.reduce(MapSet.new(), fn ancestor, acc ->
      outgoing_derives_from? =
        room
        |> ContextGraph.adjacency(object_id(ancestor))
        |> Map.get(:outgoing, [])
        |> Enum.any?(&(&1.type == :derives_from))

      if outgoing_derives_from? do
        acc
      else
        MapSet.put(acc, object_id(ancestor))
      end
    end)
    |> then(fn roots ->
      if MapSet.size(roots) == 0, do: MapSet.new([object_id]), else: roots
    end)
    |> MapSet.to_list()
  end

  defp downstream_derives_from_ids(room, context_id) do
    do_downstream_derives_from_ids(room, [context_id], MapSet.new([context_id]))
    |> MapSet.delete(context_id)
    |> MapSet.to_list()
  end

  defp do_downstream_derives_from_ids(_room, [], visited), do: visited

  defp do_downstream_derives_from_ids(room, [context_id | rest], visited) do
    {next_ids, next_visited} =
      room
      |> ContextGraph.adjacency(context_id)
      |> Map.get(:incoming, [])
      |> Enum.filter(&(&1.type == :derives_from))
      |> Enum.reduce({[], visited}, fn edge, {queued, seen} ->
        if MapSet.member?(seen, edge.from_id) do
          {queued, seen}
        else
          {[edge.from_id | queued], MapSet.put(seen, edge.from_id)}
        end
      end)

    do_downstream_derives_from_ids(room, rest ++ Enum.reverse(next_ids), next_visited)
  end

  defp put_derived_annotation(object, room) do
    annotation =
      room
      |> Map.get(:context_annotations, %{})
      |> Map.get(object_id(object), %{})

    if annotation == %{} do
      object
    else
      Map.put(object, :derived, annotation)
    end
  end

  defp contradiction_key(edge), do: {edge.from_id, edge.to_id, edge.type}

  defp continue_validation(:ok, fun), do: fun.()
  defp continue_validation(error, _fun), do: error

  defp stale_annotations_for_object(room, object) do
    superseded_ids = superseded_context_ids(room, object_id(object))

    superseded_ids
    |> Enum.flat_map(fn superseded_id ->
      room
      |> downstream_derives_from_ids(superseded_id)
      |> Enum.map(&{&1, [superseded_id]})
    end)
    |> Enum.uniq()
  end

  defp merge_annotation(annotations, invalidated_id, superseded_ids) do
    Map.update(
      annotations,
      invalidated_id,
      %{stale_ancestor: true, stale_due_to_ids: superseded_ids},
      fn annotation ->
        %{
          stale_ancestor: true,
          stale_due_to_ids:
            annotation
            |> Map.get(:stale_due_to_ids, [])
            |> Kernel.++(superseded_ids)
            |> Enum.uniq()
            |> Enum.sort()
        }
      end
    )
  end

  defp expand_reference_targets(room, participant, context_id, depth, {queued, discovered}) do
    room
    |> ContextGraph.adjacency(context_id)
    |> Map.get(:outgoing, [])
    |> Enum.filter(&(&1.type == :references))
    |> Enum.map(&ContextGraph.fetch_context_object(room, &1.to_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&visible_to_participant?(&1, participant))
    |> Enum.reduce({queued, discovered}, fn object, {queued_acc, discovered_acc} ->
      target_id = object_id(object)

      if MapSet.member?(discovered_acc, target_id) do
        {queued_acc, discovered_acc}
      else
        {[{target_id, depth + 1} | queued_acc], MapSet.put(discovered_acc, target_id)}
      end
    end)
  end

  defp superseded_context_ids(room, context_id) do
    room
    |> ContextGraph.adjacency(context_id)
    |> Map.get(:outgoing, [])
    |> Enum.filter(&(&1.type == :supersedes))
    |> Enum.map(& &1.to_id)
  end

  defp visible_to_participant?(nil, _participant), do: false

  defp visible_to_participant?(context_object, participant) do
    context_object
    |> read_tokens()
    |> Enum.any?(fn token -> visible_token?(token, context_object, participant) end)
  end

  defp read_tokens(context_object) do
    scope = Map.get(context_object, :scope) || Map.get(context_object, "scope") || %{}
    Map.get(scope, :read) || Map.get(scope, "read") || ["room"]
  end

  defp visible_token?("room", _context_object, _participant), do: true

  defp visible_token?("author", context_object, participant) do
    authored_participant_id(context_object) == participant_id(participant)
  end

  defp visible_token?(token, _context_object, participant) when is_binary(token) do
    token in [
      "participant:#{participant_id(participant)}",
      "role:#{participant_role(participant)}"
    ]
  end

  defp visible_token?(_token, _context_object, _participant), do: false

  defp human_participant?(participant) do
    Map.get(participant, :participant_kind, Map.get(participant, "participant_kind")) == "human"
  end

  defp participant_id(participant) do
    Map.get(participant, :participant_id) || Map.get(participant, "participant_id")
  end

  defp participant_role(participant) do
    Map.get(participant, :participant_role) || Map.get(participant, "participant_role")
  end

  defp authored_participant_id(context_object) do
    authored_by =
      Map.get(context_object, :authored_by) || Map.get(context_object, "authored_by") || %{}

    Map.get(authored_by, :participant_id) || Map.get(authored_by, "participant_id")
  end

  defp authority_level(context_object) do
    provenance = provenance(context_object)
    Map.get(provenance, :authority_level) || Map.get(provenance, "authority_level")
  end

  defp capability_id(context_object) do
    authored_by =
      Map.get(context_object, :authored_by) || Map.get(context_object, "authored_by") || %{}

    Map.get(authored_by, :capability_id) || Map.get(authored_by, "capability_id")
  end

  defp consumed_context_ids(nil), do: []

  defp consumed_context_ids(context_object) do
    context_object
    |> provenance()
    |> then(fn provenance ->
      Map.get(provenance, :consumed_context_ids) || Map.get(provenance, "consumed_context_ids") ||
        []
    end)
    |> Enum.uniq()
  end

  defp sets_disjoint?(left, right), do: not sets_intersect?(left, right)

  defp sets_intersect?(left, right) do
    Enum.any?(left, &(&1 in right))
  end

  defp provenance(nil), do: %{}

  defp provenance(context_object),
    do: Map.get(context_object, :provenance) || Map.get(context_object, "provenance") || %{}

  defp context_objects(room),
    do: Map.get(room, :context_objects, Map.get(room, "context_objects", []))

  defp objects_by_id(room) do
    Map.new(context_objects(room), fn object -> {object_id(object), object} end)
  end

  defp object_id(context_object) do
    Map.get(context_object, :context_id) || Map.get(context_object, "context_id")
  end

  defp object_type(nil), do: nil

  defp object_type(context_object),
    do: Map.get(context_object, :object_type) || Map.get(context_object, "object_type")
end
