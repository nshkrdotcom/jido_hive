defmodule JidoHiveTermuiConsole.Projection do
  @moduledoc false

  @ordered_types [
    "decision",
    "decision_candidate",
    "contradiction",
    "hypothesis",
    "evidence",
    "question",
    "fact",
    "message"
  ]

  @spec conversation_lines(map(), keyword()) :: [String.t()]
  def conversation_lines(snapshot, opts \\ []) do
    limit = Keyword.get(opts, :limit, 14)

    snapshot
    |> timeline_entries()
    |> Enum.take(-limit)
    |> Enum.map(&format_timeline_entry/1)
    |> default_line("No conversation yet.")
  end

  @spec display_context_objects(map()) :: [map()]
  def display_context_objects(snapshot) do
    snapshot
    |> context_objects()
    |> Enum.sort_by(fn object ->
      {type_rank(object_type(object)), String.downcase(title(object) || body(object) || "")}
    end)
  end

  @spec context_lines(map(), non_neg_integer(), keyword()) :: [String.t()]
  def context_lines(snapshot, selected_index, opts \\ []) do
    limit = Keyword.get(opts, :limit, 18)

    snapshot
    |> display_context_objects()
    |> Enum.take(limit)
    |> build_context_lines(selected_index)
    |> default_line("No structured context yet.")
  end

  defp build_context_lines(objects, selected_index) do
    {lines, _last_type, _object_index} =
      Enum.reduce(objects, {[], nil, 0}, fn object, {lines, last_type, object_index} ->
        object_type = object_type(object)

        heading_lines =
          if object_type != last_type do
            [section_heading(object_type)]
          else
            []
          end

        prefix = if object_index == selected_index, do: ">", else: " "
        label = title(object) || body(object) || object_type

        content =
          object
          |> label_with_graph_feedback(label)
          |> String.slice(0, 76)

        {lines ++ heading_lines ++ ["#{prefix} #{content}"], object_type, object_index + 1}
      end)

    lines
  end

  defp format_timeline_entry(entry) do
    participant =
      entry
      |> Map.get("metadata", %{})
      |> Map.get("participant_id")

    body = Map.get(entry, "body") || Map.get(entry, "title") || Map.get(entry, "kind") || "event"

    case participant do
      value when is_binary(value) and value != "" -> "#{value}: #{body}"
      _other -> body
    end
  end

  defp section_heading(type) do
    type
    |> String.replace("_", " ")
    |> String.upcase()
  end

  defp type_rank(type) do
    Enum.find_index(@ordered_types, &(&1 == type)) || length(@ordered_types)
  end

  defp title(object), do: Map.get(object, "title") || Map.get(object, :title)
  defp body(object), do: Map.get(object, "body") || Map.get(object, :body)

  defp object_type(object) do
    Map.get(object, "object_type") || Map.get(object, :object_type) || "message"
  end

  defp label_with_graph_feedback(object, label) do
    adjacency = adjacency(object)
    in_count = length(adjacency["incoming"])
    out_count = length(adjacency["outgoing"])

    suffixes =
      [
        "[in:#{in_count} out:#{out_count}]",
        if(stale?(object), do: "[STALE]"),
        if(conflict?(object), do: "[CONFLICT]")
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join([label | suffixes], " ")
  end

  defp stale?(object) do
    derived = Map.get(object, "derived") || Map.get(object, :derived) || %{}
    Map.get(derived, "stale_ancestor") || Map.get(derived, :stale_ancestor) || false
  end

  defp conflict?(object) do
    object_type(object) == "contradiction" or
      Enum.any?(adjacency(object)["incoming"] ++ adjacency(object)["outgoing"], fn edge ->
        (Map.get(edge, "type") || Map.get(edge, :type)) == "contradicts" ||
          (Map.get(edge, "type") || Map.get(edge, :type)) == :contradicts
      end)
  end

  defp adjacency(object) do
    Map.get(object, "adjacency") || Map.get(object, :adjacency) ||
      %{"incoming" => [], "outgoing" => []}
  end

  defp timeline_entries(snapshot),
    do: Map.get(snapshot, :timeline, Map.get(snapshot, "timeline", []))

  defp context_objects(snapshot),
    do: Map.get(snapshot, :context_objects, Map.get(snapshot, "context_objects", []))

  defp default_line([], line), do: [line]
  defp default_line(lines, _line), do: lines
end
