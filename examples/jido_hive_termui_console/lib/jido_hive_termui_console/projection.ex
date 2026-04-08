defmodule JidoHiveTermuiConsole.Projection do
  @moduledoc false

  alias JidoHiveTermuiConsole.Model

  @ordered_types [
    "decision",
    "decision_candidate",
    "contradiction",
    "hypothesis",
    "evidence",
    "question",
    "fact",
    "belief",
    "note",
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
    width = Keyword.get(opts, :width, 76)

    snapshot
    |> display_context_objects()
    |> Enum.take(limit)
    |> build_context_lines(selected_index, width)
    |> default_line("No structured context yet.")
  end

  @spec provenance_tree(map(), [map()]) :: [String.t()]
  def provenance_tree(root_object, all_objects) do
    index =
      Map.new(all_objects, fn object ->
        {context_id(object), object}
      end)

    render_provenance(root_object, index, 0, %{})
  end

  @spec conflict_sides(map(), map()) :: {[String.t()], [String.t()]}
  def conflict_sides(left_object, right_object) do
    left_lines = conflict_side_lines(left_object)
    right_lines = conflict_side_lines(right_object)
    max_len = max(length(left_lines), length(right_lines))

    {pad_lines(left_lines, max_len), pad_lines(right_lines, max_len)}
  end

  @spec event_log_display([String.t()], integer()) :: [String.t()]
  def event_log_display(lines, limit \\ 4) do
    lines
    |> Enum.take(limit)
    |> default_line("No room events yet.")
  end

  @spec lobby_rows([Model.lobby_row()], integer(), integer()) :: [String.t()]
  def lobby_rows(rows, cursor, screen_width) do
    room_width = width_fraction(screen_width, 0.20, 12)
    brief_width = width_fraction(screen_width, 0.34, 16)
    policy_width = width_fraction(screen_width, 0.16, 10)

    header =
      "  #  " <>
        String.pad_trailing("ROOM ID", room_width) <>
        "  " <>
        String.pad_trailing("BRIEF", brief_width) <>
        "  " <>
        String.pad_trailing("POLICY", policy_width) <>
        "  SLOTS  ⚑"

    divider = String.duplicate("─", min(max(screen_width - 2, 40), 120))

    rows =
      rows
      |> Enum.with_index(1)
      |> Enum.map(fn {row, index} ->
        prefix = if index - 1 == cursor, do: ">", else: " "
        flag = room_flag(row)

        status =
          if row.fetch_error do
            "[fetch error — press d to remove]"
          else
            truncate(row.brief, brief_width)
          end

        "#{prefix} #{String.pad_leading(Integer.to_string(index), 1)}  " <>
          String.pad_trailing(truncate(row.room_id, room_width), room_width) <>
          "  " <>
          String.pad_trailing(status, brief_width) <>
          "  " <>
          String.pad_trailing(truncate(row.dispatch_policy_id, policy_width), policy_width) <>
          "  " <>
          String.pad_trailing("#{row.completed_slots}/#{row.total_slots}", 5) <>
          "  " <> flag
      end)

    [header, divider] ++ rows ++ [divider]
  end

  @spec publish_preview_lines(String.t(), map(), integer()) :: [String.t()]
  def publish_preview_lines(channel, publication, width) do
    draft = Map.get(publication, "draft", Map.get(publication, :draft, %{}))

    lines =
      case channel do
        "github" ->
          [Map.get(draft, "title") || Map.get(draft, :title, "Untitled")] ++
            String.split(Map.get(draft, "body") || Map.get(draft, :body, ""), "\n")

        "notion" ->
          [Map.get(draft, "title") || Map.get(draft, :title, "Untitled")] ++
            notion_lines(Map.get(draft, "children") || Map.get(draft, :children, []))

        _other ->
          [inspect(draft, pretty: true)]
      end

    lines
    |> Enum.map(&truncate(&1, max(width - 2, 24)))
    |> default_line("No preview available.")
  end

  @spec format_timeline_entry(map()) :: String.t()
  def format_timeline_entry(entry) do
    participant = entry |> event_metadata() |> map_value("participant_id")
    body = timeline_body(entry)

    case participant do
      value when is_binary(value) and value != "" -> "#{value}: #{body}"
      _other -> to_string(body)
    end
  end

  @spec format_event_entry(map()) :: String.t()
  def format_event_entry(entry) do
    kind = Map.get(entry, "kind") || Map.get(entry, :kind) || "event"
    status = Map.get(entry, "status") || Map.get(entry, :status)
    detail = entry |> event_metadata() |> event_detail()

    [kind, status, detail]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("  ")
  end

  @spec conflict?(map()) :: boolean()
  def conflict?(object) do
    adjacency = adjacency(object)
    incoming = Map.get(adjacency, "incoming", [])
    outgoing = Map.get(adjacency, "outgoing", [])

    object_type(object) == "contradiction" or
      Enum.any?(incoming ++ outgoing, fn edge ->
        type = Map.get(edge, "type") || Map.get(edge, :type)
        type in ["contradicts", :contradicts]
      end)
  end

  @spec truncate(String.t(), pos_integer()) :: String.t()
  def truncate(str, max_width) when is_binary(str) and max_width > 0 do
    if String.length(str) <= max_width do
      str
    else
      String.slice(str, 0, max_width - 1) <> "…"
    end
  end

  defp build_context_lines(objects, selected_index, width) do
    {lines, _last_type, _object_index} =
      Enum.reduce(objects, {[], nil, 0}, fn object, {lines, last_type, object_index} ->
        current_type = object_type(object)

        heading_lines =
          if current_type != last_type do
            [section_heading(current_type)]
          else
            []
          end

        prefix = if object_index == selected_index, do: ">", else: " "
        label = title(object) || body(object) || current_type

        content =
          object
          |> label_with_graph_feedback(label)
          |> truncate(width)

        {lines ++ heading_lines ++ ["#{prefix} #{content}"], current_type, object_index + 1}
      end)

    lines
  end

  defp label_with_graph_feedback(object, label) do
    adjacency = adjacency(object)
    incoming = Map.get(adjacency, "incoming", [])
    outgoing = Map.get(adjacency, "outgoing", [])

    suffixes =
      [
        "[in:#{length(incoming)} out:#{length(outgoing)}]",
        if(stale?(object), do: "[STALE]"),
        if(conflict?(object), do: "[CONFLICT]"),
        if(binding?(object), do: "[BINDING]")
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join([label | suffixes], " ")
  end

  defp render_provenance(_object, _index, depth, _visited) when depth > 5, do: []

  defp render_provenance(object, index, depth, visited) do
    object_id = context_id(object)

    if Map.has_key?(visited, object_id) do
      [indent(depth) <> "[cycle — #{object_id}]"]
    else
      next_visited = Map.put(visited, object_id, true)
      [provenance_header(object, depth) | provenance_children(object, index, depth, next_visited)]
    end
  end

  defp conflict_side_lines(object) do
    title = title(object) || "[untitled]"
    authority = provenance_authority(object) || "advisory"
    authored_by = authored_by(object) || "[unknown]"
    confidence = confidence(object)
    relations = relations(object)

    upstream =
      relations
      |> Enum.filter(fn relation ->
        (Map.get(relation, "relation") || Map.get(relation, :relation)) in [
          "derives_from",
          :derives_from,
          "references",
          :references
        ]
      end)
      |> Enum.map(fn relation ->
        "#{Map.get(relation, "relation") || Map.get(relation, :relation)} #{Map.get(relation, "target_id") || Map.get(relation, :target_id)}"
      end)

    [
      "#{context_id(object)} [#{object_type(object)}]",
      title,
      "authored_by: #{authored_by}",
      "confidence: #{confidence}",
      "authority: #{authority}",
      "",
      body(object) || "[no body]"
    ] ++
      if upstream == [] do
        []
      else
        ["", "upstream:"] ++ Enum.map(upstream, &("  " <> &1))
      end
  end

  defp notion_lines(children) when is_list(children) do
    Enum.flat_map(children, &notion_child_lines/1)
  end

  defp notion_lines(_children), do: []

  defp plain_text(block, prefix) do
    type = Map.get(block, "type") || Map.get(block, :type)
    content = Map.get(block, type) || Map.get(block, String.to_existing_atom(to_string(type)))
    rich_text = Map.get(content, "rich_text") || Map.get(content, :rich_text) || []

    text =
      rich_text
      |> Enum.map_join(fn item ->
        Map.get(item, "plain_text") || Map.get(item, :plain_text) || ""
      end)

    [prefix <> text]
  rescue
    _error -> [prefix <> inspect(block)]
  end

  defp timeline_body(entry) do
    Map.get(entry, "body") || Map.get(entry, :body) || Map.get(entry, "title") ||
      Map.get(entry, :title) || Map.get(entry, "kind") || Map.get(entry, :kind) || "event"
  end

  defp event_metadata(entry) do
    Map.get(entry, "metadata", Map.get(entry, :metadata, %{}))
  end

  defp event_detail(metadata) do
    phase = map_value(metadata, "phase")
    participant_id = map_value(metadata, "participant_id")

    cond do
      is_binary(phase) -> "phase=#{phase}"
      is_binary(participant_id) -> "participant=#{participant_id}"
      true -> nil
    end
  end

  defp map_value(map, key) do
    atom_key =
      case key do
        "phase" -> :phase
        "participant_id" -> :participant_id
        _other -> nil
      end

    Map.get(map, key) || (atom_key && Map.get(map, atom_key))
  end

  defp provenance_header(object, depth) do
    indent(depth) <>
      type_prefix(object) <>
      truncate(title(object) || body(object) || object_type(object), 60)
  end

  defp provenance_children(object, index, depth, visited) do
    object
    |> relations()
    |> Enum.filter(&provenance_relation?/1)
    |> Enum.flat_map(&provenance_relation_lines(&1, index, depth, visited))
  end

  defp provenance_relation?(relation) do
    relation_value(relation) in ["derives_from", "references", :derives_from, :references]
  end

  defp provenance_relation_lines(relation, index, depth, visited) do
    target_id = Map.get(relation, "target_id") || Map.get(relation, :target_id)
    relation_name = relation_value(relation)

    case Map.get(index, target_id) do
      nil ->
        [indent(depth + 1) <> "#{relation_name} -> #{target_id} [not in view]"]

      child ->
        [indent(depth + 1) <> "#{relation_name} ->"] ++
          render_provenance(child, index, depth + 1, visited)
    end
  end

  defp relation_value(relation) do
    Map.get(relation, "relation") || Map.get(relation, :relation)
  end

  defp notion_child_lines(child) when is_binary(child), do: [child]

  defp notion_child_lines(child) when is_map(child) do
    child
    |> notion_prefix()
    |> render_plain_text(child)
  end

  defp notion_child_lines(child), do: [inspect(child)]

  defp notion_prefix(child) do
    case Map.get(child, "type") || Map.get(child, :type) do
      value when value in ["heading_1", :heading_1] -> "# "
      value when value in ["heading_2", :heading_2] -> "## "
      value when value in ["bulleted_list_item", :bulleted_list_item] -> "- "
      _other -> ""
    end
  end

  defp render_plain_text(prefix, block), do: plain_text(block, prefix)

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
    confidence = Map.get(uncertainty, "confidence") || Map.get(uncertainty, :confidence)

    if is_number(confidence),
      do: :io_lib.format("~.2f", [confidence]) |> IO.iodata_to_binary(),
      else: "n/a"
  end

  defp stale?(object) do
    derived = Map.get(object, "derived") || Map.get(object, :derived) || %{}
    Map.get(derived, "stale_ancestor") || Map.get(derived, :stale_ancestor) || false
  end

  defp binding?(object), do: provenance_authority(object) == "binding"

  defp room_flag(%{fetch_error: true}), do: "✗"

  defp room_flag(row) do
    cond do
      row.status == "publication_ready" -> "PUB"
      row.status == "needs_resolution" or row.flagged -> "⚡"
      row.status == "failed" -> "✗"
      true -> ""
    end
  end

  defp width_fraction(screen_width, fraction, minimum) do
    max(round(screen_width * fraction), minimum)
  end

  defp pad_lines(lines, target_len) do
    lines ++ List.duplicate("", max(target_len - length(lines), 0))
  end

  defp section_heading(type) do
    type
    |> String.replace("_", " ")
    |> String.upcase()
  end

  defp type_prefix(object), do: "[#{String.upcase(object_type(object))}] "

  defp indent(depth), do: String.duplicate("  ", depth)

  defp type_rank(type),
    do: Enum.find_index(@ordered_types, &(&1 == type)) || length(@ordered_types)

  defp context_id(object), do: Map.get(object, "context_id") || Map.get(object, :context_id)
  defp title(object), do: Map.get(object, "title") || Map.get(object, :title)
  defp body(object), do: Map.get(object, "body") || Map.get(object, :body)

  defp object_type(object) do
    Map.get(object, "object_type") || Map.get(object, :object_type) || "message"
  end

  defp adjacency(object) do
    Map.get(object, "adjacency") || Map.get(object, :adjacency) ||
      %{"incoming" => [], "outgoing" => []}
  end

  defp relations(object), do: Map.get(object, "relations") || Map.get(object, :relations) || []

  defp timeline_entries(snapshot),
    do: Map.get(snapshot, "timeline") || Map.get(snapshot, :timeline) || []

  defp context_objects(snapshot),
    do: Map.get(snapshot, "context_objects") || Map.get(snapshot, :context_objects) || []

  defp default_line([], line), do: [line]
  defp default_line(lines, _line), do: lines
end
