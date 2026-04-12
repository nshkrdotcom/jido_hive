defmodule JidoHiveContextGraph.ContributionValidator do
  @moduledoc false

  alias JidoHiveContextGraph.{ContextManager, Projector}

  @relation_types %{
    "derives_from" => :derives_from,
    "references" => :references,
    "contradicts" => :contradicts,
    "resolves" => :resolves,
    "supersedes" => :supersedes,
    "supports" => :supports,
    "blocks" => :blocks
  }

  @spec validate(map(), map()) :: :ok | {:error, term()}
  def validate(contribution, room) when is_map(contribution) and is_map(room) do
    ContextManager.validate_append(
      participant(room, contribution),
      write_intent(contribution),
      Projector.project(room)
    )
  end

  def validate(_contribution, _room), do: {:error, :invalid_contribution}

  defp participant(room, contribution) do
    participant_id = value(contribution, "participant_id")

    room
    |> participants()
    |> Enum.find(fn participant ->
      value(participant, "participant_id") == participant_id or
        value(participant, "id") == participant_id
    end)
    |> case do
      nil -> %{"participant_id" => participant_id}
      participant -> participant
    end
  end

  defp write_intent(contribution) do
    relations = Enum.flat_map(context_objects(contribution), &object_relations/1)

    %{
      drafted_object_types:
        contribution
        |> context_objects()
        |> Enum.map(&object_type/1)
        |> Enum.filter(&is_binary/1)
        |> Enum.uniq(),
      relation_targets_by_type:
        relations
        |> Enum.reduce(%{}, fn relation, acc ->
          case relation_target_entry(relation) do
            {relation_type, target_id} ->
              Map.update(acc, relation_type, [target_id], &[target_id | &1])

            nil ->
              acc
          end
        end)
        |> Map.new(fn {relation_type, target_ids} ->
          {relation_type, Enum.reverse(target_ids)}
        end),
      invalid_relations:
        relations
        |> Enum.flat_map(fn relation ->
          case invalid_relation(relation) do
            nil -> []
            invalid -> [invalid]
          end
        end)
    }
  end

  defp relation_target_entry(relation) do
    with {:ok, relation_type} <- relation_type(relation),
         target_id when is_binary(target_id) and target_id != "" <- relation_target_id(relation) do
      {relation_type, target_id}
    else
      _other -> nil
    end
  end

  defp invalid_relation(relation) do
    cond do
      invalid_relation_type?(relation) ->
        %{kind: :invalid_relation_type, relation: relation_name(relation)}

      missing_relation_target?(relation) ->
        %{kind: :missing_relation_target, relation: relation_name(relation)}

      true ->
        nil
    end
  end

  defp invalid_relation_type?(relation) do
    relation_name = relation_name(relation)
    not Map.has_key?(@relation_types, relation_name)
  end

  defp missing_relation_target?(relation) do
    case relation_type(relation) do
      {:ok, _relation_type} ->
        relation_target_id(relation) in [nil, ""]

      :error ->
        false
    end
  end

  defp relation_type(relation) do
    case Map.get(@relation_types, relation_name(relation)) do
      nil -> :error
      relation_type -> {:ok, relation_type}
    end
  end

  defp context_objects(contribution) do
    payload = value(contribution, "payload")

    case value(payload, "context_objects") do
      objects when is_list(objects) -> objects
      _other -> []
    end
  end

  defp participants(room) do
    case Map.get(room, :participants) || Map.get(room, "participants") do
      participants when is_list(participants) -> participants
      _other -> []
    end
  end

  defp object_relations(object) do
    case Map.get(object, :relations) || Map.get(object, "relations") do
      relations when is_list(relations) -> relations
      _other -> []
    end
  end

  defp object_type(object), do: Map.get(object, :object_type) || Map.get(object, "object_type")

  defp relation_name(relation), do: Map.get(relation, :relation) || Map.get(relation, "relation")

  defp relation_target_id(relation),
    do: Map.get(relation, :target_id) || Map.get(relation, "target_id")

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp value(_map, _key), do: nil

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
