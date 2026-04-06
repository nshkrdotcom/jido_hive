defmodule JidoHiveServer.Collaboration.ContextQuery do
  @moduledoc false

  @spec visible_context_objects([map()], map()) :: [map()]
  def visible_context_objects(context_objects, participant)
      when is_list(context_objects) and is_map(participant) do
    Enum.filter(context_objects, &visible?(&1, participant))
  end

  @spec list_by_type(map() | [map()], String.t() | [String.t()]) :: [map()]
  def list_by_type(source, types) do
    allowed_types =
      types
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    source
    |> context_objects()
    |> Enum.filter(&(object_type(&1) in allowed_types))
  end

  @spec list_by_author(map() | [map()], String.t()) :: [map()]
  def list_by_author(source, participant_id) when is_binary(participant_id) do
    source
    |> context_objects()
    |> Enum.filter(&(authored_id(&1) == participant_id))
  end

  def list_by_author(_source, _participant_id), do: []

  @spec adjacent_objects(map() | [map()], String.t()) :: [map()]
  def adjacent_objects(source, context_id) when is_binary(context_id) do
    objects = context_objects(source)
    selected_object = Enum.find(objects, &(object_id(&1) == context_id))

    outgoing_ids = selected_object |> relation_target_ids() |> MapSet.new()

    incoming_ids =
      objects
      |> Enum.filter(&(context_id in relation_target_ids(&1)))
      |> Enum.map(&object_id/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    adjacent_ids = MapSet.union(outgoing_ids, incoming_ids)

    objects
    |> Enum.filter(&(object_id(&1) in adjacent_ids))
    |> Enum.reject(&(object_id(&1) == context_id))
  end

  def adjacent_objects(_source, _context_id), do: []

  @spec open_questions(map() | [map()]) :: [map()]
  def open_questions(source) do
    objects = context_objects(source)

    answered_ids =
      objects
      |> Enum.flat_map(fn object ->
        if object_type(object) in ["fact", "evidence", "decision", "decision_candidate"] do
          relation_target_ids(object, ["answers"])
        else
          []
        end
      end)
      |> MapSet.new()

    objects
    |> Enum.filter(&(object_type(&1) == "question"))
    |> Enum.reject(&(object_id(&1) in answered_ids))
  end

  @spec active_hypotheses(map() | [map()]) :: [map()]
  def active_hypotheses(source), do: list_by_type(source, "hypothesis")

  @spec contradictions(map() | [map()]) :: [map()]
  def contradictions(source) do
    objects = context_objects(source)

    contradiction_ids =
      objects
      |> Enum.flat_map(&relation_target_ids(&1, ["contradicts"]))
      |> MapSet.new()

    objects
    |> Enum.filter(fn object ->
      object_type(object) == "contradiction" or object_id(object) in contradiction_ids
    end)
  end

  @spec accepted_decisions(map() | [map()]) :: [map()]
  def accepted_decisions(source), do: list_by_type(source, "decision")

  defp visible?(context_object, participant) do
    Enum.any?(read_tokens(context_object), &visible_token?(&1, context_object, participant))
  end

  defp read_tokens(context_object) do
    context_object
    |> scope()
    |> Map.get(:read, Map.get(scope(context_object), "read", ["room"]))
  end

  defp scope(context_object) do
    Map.get(context_object, :scope) || Map.get(context_object, "scope") || %{}
  end

  defp visible_token?("room", _context_object, _participant), do: true

  defp visible_token?("author", context_object, participant) do
    authored_id(context_object) == participant_id(participant)
  end

  defp visible_token?(token, _context_object, participant) when is_binary(token) do
    token in [
      "participant:#{participant_id(participant)}",
      "role:#{participant_role(participant)}"
    ]
  end

  defp visible_token?(_other, _context_object, _participant), do: false

  defp context_objects(source) when is_list(source), do: source

  defp context_objects(%{} = source),
    do: Map.get(source, :context_objects, Map.get(source, "context_objects", []))

  defp context_objects(_other), do: []

  defp relation_target_ids(context_object, allowed_relations \\ nil)

  defp relation_target_ids(context_object, allowed_relations) when is_map(context_object) do
    context_object
    |> relations()
    |> Enum.filter(fn relation ->
      is_nil(allowed_relations) or relation_name(relation) in allowed_relations
    end)
    |> Enum.map(&relation_target_id/1)
    |> Enum.reject(&is_nil/1)
  end

  defp relation_target_ids(_context_object, _allowed_relations), do: []

  defp relations(context_object) do
    Map.get(context_object, :relations) || Map.get(context_object, "relations") || []
  end

  defp relation_name(relation) do
    Map.get(relation, :relation) || Map.get(relation, "relation")
  end

  defp relation_target_id(relation) do
    Map.get(relation, :target_id) || Map.get(relation, "target_id")
  end

  defp participant_id(participant) do
    Map.get(participant, :participant_id) || Map.get(participant, "participant_id")
  end

  defp participant_role(participant) do
    Map.get(participant, :participant_role) || Map.get(participant, "participant_role")
  end

  defp authored_id(context_object) do
    authored_by =
      Map.get(context_object, :authored_by) || Map.get(context_object, "authored_by") || %{}

    Map.get(authored_by, :participant_id) || Map.get(authored_by, "participant_id")
  end

  defp object_id(context_object) do
    Map.get(context_object, :context_id) || Map.get(context_object, "context_id")
  end

  defp object_type(context_object) do
    Map.get(context_object, :object_type) || Map.get(context_object, "object_type")
  end
end
