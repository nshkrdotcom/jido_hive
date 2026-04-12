defmodule JidoHiveContextGraph.ContextGraph do
  @moduledoc false

  alias JidoHiveContextGraph.Schema.ContextEdge

  @relation_types %{
    "derives_from" => :derives_from,
    "references" => :references,
    "contradicts" => :contradicts,
    "resolves" => :resolves,
    "supersedes" => :supersedes,
    "supports" => :supports,
    "blocks" => :blocks
  }

  @default_provenance_depth 5

  @type projection :: %{
          outgoing: %{optional(String.t()) => [ContextEdge.t()]},
          incoming: %{optional(String.t()) => [ContextEdge.t()]}
        }

  @spec build(map() | [map()]) :: projection()
  def build(source) do
    objects = context_objects(source)

    edges =
      objects
      |> Enum.flat_map(&normalize_edges/1)

    empty_indexes =
      objects
      |> Enum.map(&object_id/1)
      |> Enum.reject(&is_nil/1)
      |> Map.new(&{&1, []})

    %{
      outgoing: Map.merge(empty_indexes, index_edges(edges, :from_id, &sort_edges/1)),
      incoming: Map.merge(empty_indexes, index_edges(edges, :to_id, &sort_edges/1))
    }
  end

  @spec attach(map()) :: map()
  def attach(%{} = room) do
    Map.put(room, :context_graph, build(room))
  end

  @spec adjacency(map(), String.t()) :: %{
          outgoing: [ContextEdge.t()],
          incoming: [ContextEdge.t()]
        }
  def adjacency(room, context_id) when is_binary(context_id) do
    graph = graph(room)

    %{
      outgoing: Map.get(graph.outgoing, context_id, []),
      incoming: Map.get(graph.incoming, context_id, [])
    }
  end

  def adjacency(_room, _context_id), do: %{outgoing: [], incoming: []}

  @spec provenance_chain(map(), String.t(), keyword()) :: [map()]
  def provenance_chain(room, context_id, opts \\ [])

  def provenance_chain(room, context_id, opts) when is_binary(context_id) and is_list(opts) do
    max_depth = Keyword.get(opts, :max_depth, @default_provenance_depth)
    objects_by_id = objects_by_id(room)
    graph = graph(room)

    do_provenance_chain(
      [{context_id, 0}],
      MapSet.new([context_id]),
      [],
      graph,
      objects_by_id,
      max_depth
    )
  end

  def provenance_chain(_room, _context_id, _opts), do: []

  @spec contradictions(map()) :: [ContextEdge.t()]
  def contradictions(room) do
    room
    |> graph()
    |> Map.get(:outgoing, %{})
    |> Map.values()
    |> List.flatten()
    |> Enum.filter(&(&1.type == :contradicts))
    |> Enum.reject(&resolved_contradiction?(room, &1))
    |> sort_edges()
  end

  @spec open_questions(map()) :: [map()]
  def open_questions(room) do
    objects = context_objects(room)
    objects_by_id = objects_by_id(objects)
    graph = graph(room)

    objects
    |> Enum.filter(&(object_type(&1) == "question"))
    |> Enum.reject(fn object ->
      object
      |> object_id()
      |> then(&Map.get(graph.incoming, &1, []))
      |> Enum.any?(fn edge ->
        edge.type == :resolves and
          object_type(Map.get(objects_by_id, edge.from_id)) in ["decision", "artifact"]
      end)
    end)
    |> sort_context_objects()
  end

  @spec derivation_roots(map()) :: [map()]
  def derivation_roots(room) do
    objects = context_objects(room)
    graph = graph(room)

    objects
    |> Enum.reject(fn object ->
      object
      |> object_id()
      |> then(&Map.get(graph.incoming, &1, []))
      |> Enum.any?(&(&1.type == :derives_from))
    end)
    |> sort_context_objects()
  end

  @spec fetch_context_object(map(), String.t()) :: map() | nil
  def fetch_context_object(room, context_id) when is_binary(context_id) do
    room
    |> objects_by_id()
    |> Map.get(context_id)
  end

  def fetch_context_object(_room, _context_id), do: nil

  @spec neighbors(map(), String.t()) :: [map()]
  def neighbors(room, context_id) when is_binary(context_id) do
    objects_by_id = objects_by_id(room)

    room
    |> adjacency(context_id)
    |> Map.values()
    |> List.flatten()
    |> Enum.map(fn edge ->
      if edge.from_id == context_id, do: edge.to_id, else: edge.from_id
    end)
    |> Enum.uniq()
    |> Enum.map(&Map.get(objects_by_id, &1))
    |> Enum.reject(&is_nil/1)
    |> sort_context_objects()
  end

  def neighbors(_room, _context_id), do: []

  defp do_provenance_chain([], _visited, acc, _graph, _objects_by_id, _max_depth),
    do: Enum.reverse(acc)

  defp do_provenance_chain(
         [{_context_id, depth} | rest],
         visited,
         acc,
         graph,
         objects_by_id,
         max_depth
       )
       when depth >= max_depth do
    do_provenance_chain(rest, visited, acc, graph, objects_by_id, max_depth)
  end

  defp do_provenance_chain(
         [{context_id, depth} | rest],
         visited,
         acc,
         graph,
         objects_by_id,
         max_depth
       ) do
    {parents, next_visited} =
      graph
      |> Map.get(:outgoing, %{})
      |> Map.get(context_id, [])
      |> Enum.filter(&(&1.type == :derives_from))
      |> Enum.map(&Map.get(objects_by_id, &1.to_id))
      |> Enum.reject(&is_nil/1)
      |> sort_context_objects()
      |> Enum.reduce({[], visited}, fn parent, {selected, seen} ->
        parent_id = object_id(parent)

        if MapSet.member?(seen, parent_id) do
          {selected, seen}
        else
          {[parent | selected], MapSet.put(seen, parent_id)}
        end
      end)

    parents = Enum.reverse(parents)

    next_queue =
      rest ++ Enum.map(parents, fn parent -> {object_id(parent), depth + 1} end)

    do_provenance_chain(
      next_queue,
      next_visited,
      Enum.reverse(parents) ++ acc,
      graph,
      objects_by_id,
      max_depth
    )
  end

  defp normalize_edges(%{} = context_object) do
    context_id = object_id(context_object)
    inserted_at = inserted_at(context_object)

    context_object
    |> relations()
    |> Enum.reduce([], &normalize_relation_edge(&1, &2, context_id, inserted_at))
    |> Enum.reverse()
  end

  defp normalize_edges(_context_object), do: []

  defp normalize_relation_edge(relation, acc, context_id, inserted_at) do
    case edge_from_relation(context_id, inserted_at, relation) do
      {:ok, edge} -> prepend_edge_unless_duplicate(acc, edge)
      :skip -> acc
    end
  end

  defp prepend_edge_unless_duplicate(acc, edge) do
    if Enum.any?(acc, &same_edge?(&1, edge)), do: acc, else: [edge | acc]
  end

  defp index_edges(edges, field, sorter) do
    edges
    |> Enum.group_by(&Map.fetch!(&1, field))
    |> Map.new(fn {id, grouped_edges} -> {id, sorter.(grouped_edges)} end)
  end

  defp graph(%{context_graph: %{outgoing: _, incoming: _}} = room), do: room.context_graph
  defp graph(room), do: build(room)

  defp resolved_contradiction?(room, %ContextEdge{} = edge) do
    contradiction_pair = pair(edge.from_id, edge.to_id)
    graph = graph(room)

    graph.outgoing
    |> Map.values()
    |> List.flatten()
    |> Enum.filter(&(&1.type == :resolves))
    |> Enum.group_by(& &1.from_id, & &1.to_id)
    |> Enum.any?(fn {_resolver_id, target_ids} ->
      target_ids
      |> Enum.uniq()
      |> pair_memberships()
      |> Enum.any?(&(&1 == contradiction_pair))
    end)
  end

  defp pair_memberships(target_ids) do
    for left <- target_ids,
        right <- target_ids,
        left < right do
      pair(left, right)
    end
  end

  defp pair(left, right) when left <= right, do: {left, right}
  defp pair(left, right), do: {right, left}

  defp sort_edges(edges) do
    Enum.sort_by(edges, fn edge -> {inserted_at(edge), edge.from_id, edge.to_id, edge.type} end)
  end

  defp sort_context_objects(objects) do
    Enum.sort_by(objects, fn object -> {inserted_at(object), object_id(object)} end)
  end

  defp objects_by_id(source) do
    source
    |> context_objects()
    |> Map.new(fn object -> {object_id(object), object} end)
  end

  defp context_objects(source) when is_list(source), do: source

  defp context_objects(%{} = source),
    do: Map.get(source, :context_objects, Map.get(source, "context_objects", []))

  defp context_objects(_source), do: []

  defp relation_type(relation) do
    case Map.get(@relation_types, relation_name(relation)) do
      nil -> :error
      type -> {:ok, type}
    end
  end

  defp same_edge?(left, right) do
    left.from_id == right.from_id and left.to_id == right.to_id and left.type == right.type
  end

  defp edge_from_relation(context_id, inserted_at, relation) do
    case {relation_type(relation), relation_target_id(relation)} do
      {{:ok, type}, target_id} when is_binary(target_id) and target_id != "" ->
        {:ok,
         %ContextEdge{from_id: context_id, to_id: target_id, type: type, inserted_at: inserted_at}}

      _other ->
        :skip
    end
  end

  defp relations(context_object) do
    Map.get(context_object, :relations) || Map.get(context_object, "relations") || []
  end

  defp relation_name(relation) do
    Map.get(relation, :relation) || Map.get(relation, "relation")
  end

  defp relation_target_id(relation) do
    Map.get(relation, :target_id) || Map.get(relation, "target_id")
  end

  defp object_id(context_object) do
    Map.get(context_object, :context_id) || Map.get(context_object, "context_id")
  end

  defp object_type(nil), do: nil

  defp object_type(context_object),
    do: Map.get(context_object, :object_type) || Map.get(context_object, "object_type")

  defp inserted_at(%ContextEdge{inserted_at: %DateTime{} = inserted_at}), do: inserted_at

  defp inserted_at(context_object) do
    case Map.get(context_object, :inserted_at) || Map.get(context_object, "inserted_at") do
      %DateTime{} = inserted_at -> inserted_at
      _other -> ~U[1970-01-01 00:00:00Z]
    end
  end
end
