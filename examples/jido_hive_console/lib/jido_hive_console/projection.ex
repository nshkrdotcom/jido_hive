defmodule JidoHiveConsole.Projection do
  @moduledoc false

  alias JidoHiveClient.RoomInsight
  alias JidoHiveConsole.Model

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

  @section_headings %{
    "belief" => "WORKING BELIEFS",
    "contradiction" => "CONFLICTS",
    "decision" => "DECISIONS",
    "decision_candidate" => "DECISION CANDIDATES",
    "evidence" => "EVIDENCE",
    "fact" => "FACTS",
    "hypothesis" => "WORKING HYPOTHESES",
    "message" => "MESSAGES",
    "note" => "NOTES",
    "question" => "OPEN QUESTIONS"
  }

  @spec conversation_lines(map(), keyword()) :: [String.t()]
  def conversation_lines(snapshot, opts \\ []) do
    limit = Keyword.get(opts, :limit, 14)
    participant_id = Keyword.get(opts, :participant_id)
    pending_submit = Keyword.get(opts, :pending_submit)

    snapshot
    |> conversation_entries(participant_id, pending_submit)
    |> Enum.take(-limit)
    |> Enum.map(&format_conversation_entry/1)
    |> default_line("No conversation yet.")
  end

  @spec display_context_objects(map()) :: [map()]
  def display_context_objects(snapshot) do
    snapshot
    |> context_objects()
    |> Enum.reject(&duplicate_hidden?/1)
    |> Enum.sort_by(fn object ->
      {type_rank(object_type(object)), String.downcase(title(object) || body(object) || "")}
    end)
  end

  @spec context_lines(map(), non_neg_integer(), keyword()) :: [String.t()]
  def context_lines(snapshot, selected_index, opts \\ []) do
    limit = Keyword.get(opts, :limit, 18)
    width = Keyword.get(opts, :width, 76)
    objects = display_context_objects(snapshot)

    objects
    |> Enum.take(limit)
    |> build_context_lines(selected_index, width, objects)
    |> default_line("No structured context yet.")
  end

  @spec workflow_summary(map()) :: %{
          objective: String.t(),
          stage: String.t(),
          next_action: String.t(),
          reason: String.t(),
          graph_counts: String.t(),
          focus_queue: [String.t()],
          publish_state: String.t()
        }
  def workflow_summary(snapshot) do
    control_plane = RoomInsight.control_plane(snapshot)

    %{
      objective: control_plane.objective,
      stage: control_plane.stage,
      next_action: control_plane.next_action,
      reason: control_plane.reason,
      graph_counts: graph_counts_line(control_plane.graph_counts),
      focus_queue: Enum.map(control_plane.focus_queue, &format_focus_item/1),
      publish_state: publish_state_line(control_plane)
    }
  end

  @spec selected_context_detail_lines(map() | nil, map() | [map()] | nil) :: [String.t()]
  def selected_context_detail_lines(nil, _scope), do: ["No context selected."]

  def selected_context_detail_lines(object, scope) when is_map(object) do
    {incoming, outgoing} = graph_edges(object, scope)
    snapshot = detail_scope(scope)
    {:ok, trace} = RoomInsight.provenance_trace(snapshot, context_id(object))

    relation_lines =
      case relations(object) do
        [] ->
          ["Relations: none"]

        relation_entries ->
          ["Relations"] ++
            Enum.map(relation_entries, fn relation ->
              "- #{relation_value(relation)} #{relation_target_id(relation)}"
            end)
      end

    [
      "Context ID: #{context_id(object)}",
      "Type: #{object_type(object)}",
      "Authority: #{provenance_authority(object) || "advisory"}",
      "Confidence: #{confidence(object)}",
      "Graph: #{length(incoming)} incoming · #{length(outgoing)} outgoing"
    ] ++
      duplicate_detail_lines(object) ++
      recommended_action_lines(trace) ++
      [
        "",
        "Title",
        title(object) || "[untitled]",
        "",
        "Body",
        body(object) || "[no body]"
      ] ++
      if relation_lines == ["Relations: none"] do
        ["", "Relations: none"]
      else
        [""] ++ relation_lines
      end
  end

  @spec provenance_tree(map(), [map()]) :: [String.t()]
  def provenance_tree(root_object, all_objects) do
    case RoomInsight.provenance_trace(
           %{"context_objects" => all_objects},
           context_id(root_object)
         ) do
      {:ok, trace} ->
        Enum.map(trace.trace, &format_provenance_entry/1)

      {:error, :not_found} ->
        []
    end
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

  @spec format_conversation_entry(map()) :: String.t()
  def format_conversation_entry(entry) do
    participant = conversation_participant_id(entry)
    contribution_type = map_value(entry, "contribution_type")
    body = conversation_body(entry)
    pending? = map_value(entry, "local_status") == "pending"
    "#{conversation_prefix(participant, contribution_type, pending?)}: #{body}"
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

  @spec conflict?(map(), map() | [map()] | nil) :: boolean()
  def conflict?(object, scope \\ nil) do
    {incoming, outgoing} = graph_edges(object, scope)

    object_type(object) == "contradiction" or
      Enum.any?(incoming ++ outgoing, &contradiction_edge?/1)
  end

  @spec truncate(String.t(), pos_integer()) :: String.t()
  def truncate(str, max_width) when is_binary(str) and max_width > 0 do
    if String.length(str) <= max_width do
      str
    else
      String.slice(str, 0, max_width - 1) <> "…"
    end
  end

  defp build_context_lines(objects, selected_index, width, all_objects) do
    duplicates = duplicate_label_counts(objects)

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
        label = display_label(object, duplicates)

        content =
          object
          |> label_with_graph_feedback(label, all_objects)
          |> truncate(width)

        {lines ++ heading_lines ++ ["#{prefix} #{content}"], current_type, object_index + 1}
      end)

    lines
  end

  defp label_with_graph_feedback(object, label, scope) do
    {incoming, outgoing} = graph_edges(object, scope)

    suffixes =
      [
        edge_counts_suffix(incoming, outgoing),
        duplicate_suffix(object),
        if(stale?(object), do: "[STALE]"),
        if(conflict?(object, scope), do: "[CONFLICT]"),
        if(binding?(object), do: "[BINDING]")
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join([label | suffixes], " ")
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

  defp duplicate_hidden?(object), do: duplicate_status(object) == "duplicate"

  defp duplicate_suffix(object) do
    case duplicate_hidden_count(object) do
      count when count > 0 -> "[DUP:#{count}]"
      _other -> nil
    end
  end

  defp duplicate_detail_lines(object) do
    case duplicate_size(object) do
      size when size > 1 ->
        [
          "Duplicates: #{size - 1} collapsed under #{duplicate_canonical_context_id(object) || context_id(object)}",
          "Group: #{Enum.join(duplicate_context_ids(object), ", ")}"
        ]

      _other ->
        []
    end
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

  defp duplicate_context_ids(object) do
    derived = Map.get(object, "derived") || Map.get(object, :derived) || %{}
    Map.get(derived, "duplicate_context_ids") || Map.get(derived, :duplicate_context_ids) || []
  end

  defp duplicate_canonical_context_id(object) do
    derived = Map.get(object, "derived") || Map.get(object, :derived) || %{}
    Map.get(derived, "canonical_context_id") || Map.get(derived, :canonical_context_id)
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
    Map.get(@section_headings, type, type |> String.replace("_", " ") |> String.upcase())
  end

  defp publish_state_line(%{publish_ready: true}), do: "Publish ready"

  defp publish_state_line(%{publish_blockers: [first | _rest]}) when is_binary(first),
    do: "Publish blocked: #{first}"

  defp publish_state_line(_summary), do: "Publish blocked"

  defp format_focus_item(focus_item) do
    kind =
      focus_item
      |> Map.get(:kind, Map.get(focus_item, "kind", "focus"))
      |> to_string()
      |> String.replace("_", " ")

    context_id =
      Map.get(focus_item, :context_id) || Map.get(focus_item, "context_id") || "unknown"

    action =
      Map.get(focus_item, :action) || Map.get(focus_item, "action") || "Inspect selected detail"

    "#{kind} #{context_id}: #{action}"
  end

  defp recommended_action_lines(%{recommended_actions: []}), do: []

  defp recommended_action_lines(%{recommended_actions: actions}) do
    ["", "Recommended Actions"] ++
      Enum.map(actions, fn action ->
        label = Map.get(action, :label) || Map.get(action, "label")
        shortcut = Map.get(action, :shortcut) || Map.get(action, "shortcut")
        "- #{label} (#{shortcut})"
      end)
  end

  defp detail_scope(scope) when is_map(scope), do: scope
  defp detail_scope(scope) when is_list(scope), do: %{"context_objects" => scope}
  defp detail_scope(_scope), do: %{"context_objects" => []}

  defp format_provenance_entry(%{depth: 0} = entry) do
    "[#{entry.object_type |> to_string() |> String.upcase()}] #{truncate(entry.title, 60)}"
  end

  defp format_provenance_entry(%{cycle: true} = entry) do
    indent(entry.depth) <> "#{entry.via} -> [cycle — #{entry.context_id}]"
  end

  defp format_provenance_entry(entry) do
    indent(entry.depth) <>
      "#{entry.via} -> [#{entry.object_type |> to_string() |> String.upcase()}] #{truncate(entry.title, 60)}"
  end

  defp graph_counts_line(graph_counts) do
    [:decisions, :questions, :contradictions, :duplicates, :stale, :total]
    |> Enum.map(fn key ->
      {key, Map.get(graph_counts, key) || Map.get(graph_counts, Atom.to_string(key))}
    end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == 0 end)
    |> Enum.map_join("  |  ", fn {key, value} ->
      "#{value} #{humanize_count_key(key, value)}"
    end)
    |> case do
      "" -> "0 total"
      line -> line
    end
  end

  defp humanize_count_key(key, value) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> then(fn label ->
      if value == 1 and String.ends_with?(label, "s") do
        String.trim_trailing(label, "s")
      else
        label
      end
    end)
  end

  defp duplicate_label_counts(objects) do
    objects
    |> Enum.map(&(title(&1) || body(&1) || object_type(&1)))
    |> Enum.frequencies()
  end

  defp display_label(object, duplicates) do
    label = title(object) || body(object) || object_type(object)

    if (Map.get(duplicates, label, 0) > 1 or duplicate_hidden_count(object) > 0) and
         is_binary(context_id(object)) do
      "#{label} · #{context_id(object)}"
    else
      label
    end
  end

  defp edge_counts_suffix(incoming, outgoing) do
    if incoming == [] and outgoing == [] do
      nil
    else
      "[in:#{length(incoming)} out:#{length(outgoing)}]"
    end
  end

  defp indent(depth), do: String.duplicate("  ", depth)

  defp type_rank(type),
    do: Enum.find_index(@ordered_types, &(&1 == type)) || length(@ordered_types)

  defp context_id(object), do: Map.get(object, "context_id") || Map.get(object, :context_id)
  defp title(object), do: Map.get(object, "title") || Map.get(object, :title)
  defp body(object), do: Map.get(object, "body") || Map.get(object, :body)

  defp object_type(object) do
    Map.get(object, "object_type") || Map.get(object, :object_type) || "message"
  end

  defp graph_edges(object, scope) do
    if has_adjacency?(object) do
      adjacency = adjacency(object)
      incoming = Map.get(adjacency, "incoming", Map.get(adjacency, :incoming, []))
      outgoing = Map.get(adjacency, "outgoing", Map.get(adjacency, :outgoing, []))
      {incoming, outgoing}
    else
      object_id = context_id(object)
      {incoming_relation_edges(scope, object_id), outgoing_relation_edges(object)}
    end
  end

  defp has_adjacency?(object) do
    Map.has_key?(object, "adjacency") or Map.has_key?(object, :adjacency)
  end

  defp incoming_relation_edges(scope, target_id) when is_binary(target_id) do
    scope_objects(scope)
    |> Enum.flat_map(fn object ->
      source_id = context_id(object)

      object
      |> relations()
      |> Enum.filter(&(relation_target_id(&1) == target_id))
      |> Enum.map(fn relation ->
        %{
          "type" => relation_type(relation),
          "from_id" => source_id,
          "target_id" => target_id
        }
      end)
    end)
  end

  defp incoming_relation_edges(_scope, _target_id), do: []

  defp outgoing_relation_edges(object) do
    Enum.map(relations(object), fn relation ->
      %{
        "type" => relation_type(relation),
        "target_id" => relation_target_id(relation)
      }
    end)
  end

  defp contradiction_edge?(edge) do
    relation_type(edge) in ["contradicts", :contradicts]
  end

  defp adjacency(object) do
    Map.get(object, "adjacency") || Map.get(object, :adjacency) ||
      %{"incoming" => [], "outgoing" => []}
  end

  defp relation_type(relation) do
    Map.get(relation, "type") || Map.get(relation, :type) || Map.get(relation, "relation") ||
      Map.get(relation, :relation)
  end

  defp relation_target_id(relation) do
    Map.get(relation, "target_id") || Map.get(relation, :target_id)
  end

  defp relations(object), do: Map.get(object, "relations") || Map.get(object, :relations) || []

  defp scope_objects(%{} = snapshot), do: context_objects(snapshot)
  defp scope_objects(objects) when is_list(objects), do: objects
  defp scope_objects(_other), do: []

  defp contributions(snapshot),
    do: Map.get(snapshot, "contributions") || Map.get(snapshot, :contributions) || []

  defp context_objects(snapshot),
    do: Map.get(snapshot, "context_objects") || Map.get(snapshot, :context_objects) || []

  defp conversation_entries(snapshot, participant_id, pending_submit) do
    entries =
      case contributions(snapshot) do
        [] ->
          snapshot
          |> context_objects()
          |> Enum.filter(&(object_type(&1) == "message"))
          |> Enum.map(&message_object_entry/1)

        listed ->
          listed
      end

    entries ++ pending_conversation_entries(entries, participant_id, pending_submit)
  end

  defp pending_conversation_entries(entries, participant_id, %{text: text})
       when is_binary(text) and is_binary(participant_id) do
    normalized_text = String.trim(text)

    cond do
      normalized_text == "" ->
        []

      Enum.any?(entries, &conversation_matches?(&1, participant_id, normalized_text)) ->
        []

      true ->
        [
          %{
            "participant_id" => participant_id,
            "contribution_type" => "chat",
            "summary" => normalized_text,
            "local_status" => "pending"
          }
        ]
    end
  end

  defp pending_conversation_entries(_entries, _participant_id, _pending_submit), do: []

  defp conversation_matches?(entry, participant_id, normalized_text) do
    conversation_participant_id(entry) == participant_id and
      String.trim(conversation_body(entry)) == normalized_text
  end

  defp message_object_entry(object) do
    %{
      "participant_id" => authored_by_participant_id(object),
      "contribution_type" => "chat",
      "summary" => body(object) || title(object) || ""
    }
  end

  defp conversation_participant_id(entry) do
    map_value(entry, "participant_id") ||
      get_in(entry, ["authored_by", "participant_id"]) ||
      get_in(entry, [:authored_by, :participant_id])
  end

  defp authored_by_participant_id(object) do
    get_in(object, ["authored_by", "participant_id"]) ||
      get_in(object, [:authored_by, :participant_id])
  end

  defp conversation_body(entry) do
    entry
    |> message_body_from_entry()
    |> case do
      value when is_binary(value) and value != "" ->
        value

      _other ->
        map_value(entry, "summary") ||
          map_value(entry, "body") ||
          map_value(entry, "title") ||
          "(empty)"
    end
  end

  defp message_body_from_entry(entry) do
    entry
    |> map_value("context_objects")
    |> case do
      objects when is_list(objects) ->
        objects
        |> Enum.find(&(object_type(&1) == "message"))
        |> case do
          nil -> nil
          object -> body(object) || title(object)
        end

      _other ->
        nil
    end
  end

  defp conversation_prefix(participant, contribution_type, pending?) do
    if present_participant?(participant) do
      participant_prefix(participant, contribution_type, pending?)
    else
      fallback_conversation_prefix(contribution_type, pending?)
    end
  end

  defp present_participant?(participant), do: is_binary(participant) and participant != ""

  defp participant_prefix(participant, _contribution_type, true), do: "#{participant} (sending)"

  defp participant_prefix(participant, contribution_type, false)
       when contribution_type in [nil, "", "chat"],
       do: participant

  defp participant_prefix(participant, contribution_type, false),
    do: "#{participant} [#{contribution_type}]"

  defp fallback_conversation_prefix(_contribution_type, true), do: "pending"

  defp fallback_conversation_prefix(contribution_type, false)
       when is_binary(contribution_type) and contribution_type != "",
       do: contribution_type

  defp fallback_conversation_prefix(_contribution_type, false), do: "system"

  defp default_line([], line), do: [line]
  defp default_line(lines, _line), do: lines
end
