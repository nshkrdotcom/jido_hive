defmodule JidoHiveServer.Collaboration.ContextQuery do
  @moduledoc false

  @spec visible_context_objects([map()], map()) :: [map()]
  def visible_context_objects(context_objects, participant)
      when is_list(context_objects) and is_map(participant) do
    Enum.filter(context_objects, &visible?(&1, participant))
  end

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
end
