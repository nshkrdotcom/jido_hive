defmodule JidoHiveServer.Collaboration.ContextDeduper do
  @moduledoc false

  @dedupable_types MapSet.new([
                     "artifact",
                     "belief",
                     "claim",
                     "constraint",
                     "decision",
                     "decision_candidate",
                     "evidence",
                     "fact",
                     "hypothesis",
                     "note",
                     "question"
                   ])

  @type duplicate_group :: %{
          duplicate_group_id: String.t(),
          canonical_context_id: String.t(),
          duplicate_context_ids: [String.t()],
          duplicate_size: pos_integer()
        }

  @spec rebuild_annotations(map() | [map()]) :: %{optional(String.t()) => map()}
  def rebuild_annotations(source) do
    source
    |> duplicate_groups()
    |> Enum.reduce(%{}, &put_group_annotations/2)
  end

  @spec duplicate_groups(map() | [map()]) :: [duplicate_group()]
  def duplicate_groups(source) do
    source
    |> context_objects()
    |> Enum.filter(&dedupable?/1)
    |> Enum.group_by(&fingerprint/1)
    |> Enum.flat_map(fn {fingerprint, grouped_objects} ->
      case sort_group(grouped_objects) do
        [_single] ->
          []

        sorted_objects ->
          duplicate_context_ids = Enum.map(sorted_objects, &context_id/1)

          [
            %{
              duplicate_group_id: duplicate_group_id(fingerprint),
              canonical_context_id: hd(duplicate_context_ids),
              duplicate_context_ids: duplicate_context_ids,
              duplicate_size: length(duplicate_context_ids)
            }
          ]
      end
    end)
    |> Enum.sort_by(&{&1.canonical_context_id, &1.duplicate_group_id})
  end

  @spec canonical_context_objects(map() | [map()]) :: [map()]
  def canonical_context_objects(source) do
    hidden_ids =
      source
      |> duplicate_groups()
      |> Enum.flat_map(fn group -> tl(group.duplicate_context_ids) end)
      |> MapSet.new()

    source
    |> context_objects()
    |> Enum.reject(fn object ->
      MapSet.member?(hidden_ids, context_id(object))
    end)
  end

  defp dedupable?(object) do
    MapSet.member?(@dedupable_types, object_type(object))
  end

  defp put_group_annotations(group, annotations) do
    group.duplicate_context_ids
    |> Enum.with_index()
    |> Enum.reduce(annotations, fn {context_id, rank}, acc ->
      Map.put(acc, context_id, annotation_for(group, rank))
    end)
  end

  defp annotation_for(group, rank) do
    %{
      duplicate_group_id: group.duplicate_group_id,
      canonical_context_id: group.canonical_context_id,
      duplicate_context_ids: group.duplicate_context_ids,
      duplicate_rank: rank,
      duplicate_size: group.duplicate_size,
      duplicate_status: duplicate_status(rank)
    }
  end

  defp duplicate_status(0), do: "canonical"
  defp duplicate_status(_rank), do: "duplicate"

  defp fingerprint(object) do
    %{
      object_type: object_type(object),
      title: normalize_text(title(object)),
      body: normalize_text(body(object)),
      data: normalize_value(data(object)),
      relations:
        object
        |> relations()
        |> Enum.map(fn relation ->
          %{
            relation: normalize_text(relation_value(relation)),
            target_id: normalize_text(relation_target_id(relation))
          }
        end)
        |> Enum.sort()
    }
  end

  defp duplicate_group_id(fingerprint) do
    encoded =
      fingerprint
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "dup-" <> binary_part(encoded, 0, 12)
  end

  defp sort_group(objects) do
    Enum.sort_by(objects, fn object ->
      {inserted_at(object), context_id(object)}
    end)
  end

  defp normalize_text(nil), do: nil

  defp normalize_text(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.downcase()
  end

  defp normalize_text(other), do: other

  defp normalize_value(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} -> {to_string(key), normalize_value(nested_value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value

  defp context_objects(source) when is_list(source), do: source

  defp context_objects(%{} = source),
    do: Map.get(source, :context_objects, Map.get(source, "context_objects", []))

  defp context_objects(_source), do: []

  defp context_id(object), do: Map.get(object, :context_id) || Map.get(object, "context_id")
  defp object_type(object), do: Map.get(object, :object_type) || Map.get(object, "object_type")
  defp title(object), do: Map.get(object, :title) || Map.get(object, "title")
  defp body(object), do: Map.get(object, :body) || Map.get(object, "body")
  defp data(object), do: Map.get(object, :data) || Map.get(object, "data") || %{}
  defp relations(object), do: Map.get(object, :relations) || Map.get(object, "relations") || []

  defp relation_value(relation),
    do: Map.get(relation, :relation) || Map.get(relation, "relation")

  defp relation_target_id(relation),
    do: Map.get(relation, :target_id) || Map.get(relation, "target_id")

  defp inserted_at(object) do
    Map.get(object, :inserted_at) || Map.get(object, "inserted_at") ||
      ~U[1970-01-01 00:00:00Z]
  end
end
