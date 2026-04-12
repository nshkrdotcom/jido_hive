defmodule JidoHiveClient.RoomWorkspace do
  @moduledoc """
  Structured room workspace data for headless clients and terminal frontends.
  """

  alias JidoHiveClient.{RoomInsight, RoomWorkflow}

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

  @map_value_keys %{
    "body" => :body,
    "contribution_type" => :contribution_type,
    "local_status" => :local_status,
    "participant_id" => :participant_id,
    "summary" => :summary,
    "title" => :title
  }

  @type graph_item :: %{
          context_id: String.t() | nil,
          object_type: String.t(),
          title: String.t(),
          body: String.t() | nil,
          selected?: boolean(),
          graph: %{incoming: non_neg_integer(), outgoing: non_neg_integer()},
          flags: %{
            binding: boolean(),
            conflict: boolean(),
            stale: boolean(),
            duplicate_count: non_neg_integer()
          }
        }

  @type t :: %{
          room_id: String.t() | nil,
          status: String.t(),
          objective: String.t(),
          control_plane: map(),
          conversation: [map()],
          graph_sections: [%{title: String.t(), items: [graph_item()]}],
          detail_index: %{optional(String.t()) => map()},
          selected_context_id: String.t() | nil,
          selected_detail: map() | nil,
          workflow_summary: map(),
          events: [map()]
        }

  @spec build(map(), keyword()) :: t()
  def build(snapshot, opts \\ [])

  def build(snapshot, opts) when is_map(snapshot) do
    snapshot = project_snapshot(snapshot)
    selected_context_id = Keyword.get(opts, :selected_context_id)
    control_plane = RoomInsight.control_plane(snapshot)
    display_objects = display_context_objects(snapshot)
    selected = selected_object(display_objects, selected_context_id)

    detail_index =
      Map.new(display_objects, fn object ->
        {context_id(object), selected_detail(object, snapshot)}
      end)

    %{
      room_id: Map.get(snapshot, "room_id"),
      status: Map.get(snapshot, "status", "unknown"),
      objective: Map.get(snapshot, "brief") || control_plane.objective,
      control_plane: control_plane,
      conversation:
        conversation_entries(
          snapshot,
          Keyword.get(opts, :participant_id),
          Keyword.get(opts, :pending_submit)
        ),
      graph_sections: graph_sections(display_objects, selected_context_id, snapshot),
      detail_index: detail_index,
      selected_context_id: selected_context_id || context_id(selected),
      selected_detail: Map.get(detail_index, selected_context_id || context_id(selected)),
      workflow_summary: RoomWorkflow.summary(snapshot),
      events: event_entries(snapshot)
    }
  end

  def build(_snapshot, _opts), do: build(%{})

  @spec provenance(map(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def provenance(snapshot, context_id),
    do: snapshot |> project_snapshot() |> RoomInsight.provenance_trace(context_id)

  @spec display_context_objects(map()) :: [map()]
  def display_context_objects(snapshot) do
    snapshot
    |> project_snapshot()
    |> context_objects()
    |> Enum.reject(&duplicate_hidden?/1)
    |> Enum.sort_by(fn object ->
      {type_rank(object_type(object)), String.downcase(title(object) || body(object) || "")}
    end)
  end

  @spec selected_detail(map() | nil, map()) :: map() | nil
  def selected_detail(nil, _snapshot), do: nil

  def selected_detail(object, snapshot) do
    {incoming, outgoing} = graph_edges(object, snapshot)

    {:ok, trace} =
      RoomInsight.provenance_trace(detail_scope(snapshot), context_id(object))

    %{
      context_id: context_id(object),
      object_type: object_type(object),
      authority: provenance_authority(object) || "advisory",
      confidence: confidence(object),
      title: title(object) || "[untitled]",
      body: body(object) || "[no body]",
      graph: %{incoming: length(incoming), outgoing: length(outgoing)},
      relations:
        Enum.map(relations(object), fn relation ->
          %{
            relation: relation_value(relation),
            target_id: relation_target_id(relation)
          }
        end),
      duplicates: %{
        hidden_count: duplicate_hidden_count(object),
        canonical_context_id: duplicate_canonical_context_id(object) || context_id(object),
        context_ids: duplicate_context_ids(object)
      },
      recommended_actions: trace.recommended_actions
    }
  end

  defp graph_sections(objects, selected_context_id, snapshot) do
    objects
    |> Enum.group_by(&section_heading(object_type(&1)))
    |> sort_sections()
    |> Enum.map(fn {title, grouped_objects} ->
      %{
        title: title,
        items: Enum.map(grouped_objects, &graph_item(&1, selected_context_id, snapshot))
      }
    end)
  end

  defp sort_sections(grouped) do
    grouped
    |> Enum.sort_by(fn {_title, [first | _rest]} -> type_rank(object_type(first)) end)
  end

  defp graph_item(object, selected_context_id, snapshot) do
    {incoming, outgoing} = graph_edges(object, snapshot)

    %{
      context_id: context_id(object),
      object_type: object_type(object),
      title: display_label(object, snapshot),
      body: body(object),
      selected?: context_id(object) == selected_context_id,
      graph: %{incoming: length(incoming), outgoing: length(outgoing)},
      flags: %{
        binding: binding?(object),
        conflict: conflict?(object, snapshot),
        stale: stale?(object),
        duplicate_count: duplicate_hidden_count(object)
      }
    }
  end

  defp selected_object(objects, nil), do: List.first(objects)

  defp selected_object(objects, selected_context_id) do
    Enum.find(objects, &(context_id(&1) == selected_context_id)) || List.first(objects)
  end

  defp event_entries(snapshot) do
    snapshot
    |> Map.get("timeline", [])
    |> Enum.map(fn entry ->
      %{
        body:
          Map.get(entry, "body") || Map.get(entry, :body) || Map.get(entry, "kind") ||
            Map.get(entry, :kind) || "event",
        participant_id:
          get_in(entry, ["metadata", "participant_id"]) ||
            get_in(entry, [:metadata, :participant_id]),
        kind: Map.get(entry, "kind") || Map.get(entry, :kind) || "event",
        status: Map.get(entry, "status") || Map.get(entry, :status)
      }
    end)
  end

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

    entries
    |> Enum.map(&normalize_conversation_entry/1)
    |> Kernel.++(pending_conversation_entries(entries, participant_id, pending_submit))
  end

  defp normalize_conversation_entry(entry) do
    %{
      participant_id: conversation_participant_id(entry),
      contribution_type: map_value(entry, "contribution_type") || "chat",
      body: conversation_body(entry),
      pending?: map_value(entry, "local_status") == "pending"
    }
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
            participant_id: participant_id,
            contribution_type: "chat",
            body: normalized_text,
            pending?: true
          }
        ]
    end
  end

  defp pending_conversation_entries(_entries, _participant_id, _pending_submit), do: []

  defp project_snapshot(snapshot) when is_map(snapshot),
    do: JidoHiveContextGraph.project(snapshot)

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
    case map_value(entry, "summary") || map_value(entry, "body") || map_value(entry, "title") do
      value when is_binary(value) and value != "" -> value
      _other -> "(empty)"
    end
  end

  defp display_label(object, snapshot) do
    label = title(object) || body(object) || object_type(object)
    duplicates = duplicate_label_counts(display_context_objects(snapshot))

    if (Map.get(duplicates, label, 0) > 1 or duplicate_hidden_count(object) > 0) and
         is_binary(context_id(object)) do
      "#{label} · #{context_id(object)}"
    else
      label
    end
  end

  defp detail_scope(scope) when is_map(scope), do: scope

  defp graph_edges(object, snapshot) do
    if has_adjacency?(object) do
      adjacency = adjacency(object)
      incoming = Map.get(adjacency, "incoming", Map.get(adjacency, :incoming, []))
      outgoing = Map.get(adjacency, "outgoing", Map.get(adjacency, :outgoing, []))
      {incoming, outgoing}
    else
      object_id = context_id(object)
      {incoming_relation_edges(snapshot, object_id), outgoing_relation_edges(object)}
    end
  end

  defp incoming_relation_edges(scope, target_id) when is_binary(target_id) do
    scope
    |> context_objects()
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

  defp conflict?(object, snapshot) do
    {incoming, outgoing} = graph_edges(object, snapshot)

    object_type(object) == "contradiction" or
      Enum.any?(incoming ++ outgoing, &(relation_type(&1) in ["contradicts", :contradicts]))
  end

  defp duplicate_label_counts(objects) do
    objects
    |> Enum.map(&(title(&1) || body(&1) || object_type(&1)))
    |> Enum.frequencies()
  end

  defp duplicate_hidden?(object), do: duplicate_status(object) == "duplicate"

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

  defp provenance_authority(object) do
    provenance = Map.get(object, "provenance") || Map.get(object, :provenance) || %{}
    Map.get(provenance, "authority_level") || Map.get(provenance, :authority_level)
  end

  defp section_heading(type) do
    Map.get(@section_headings, type, type |> String.replace("_", " ") |> String.upcase())
  end

  defp type_rank(type),
    do: Enum.find_index(@ordered_types, &(&1 == type)) || length(@ordered_types)

  defp has_adjacency?(object) do
    Map.has_key?(object, "adjacency") or Map.has_key?(object, :adjacency)
  end

  defp adjacency(object) do
    Map.get(object, "adjacency") || Map.get(object, :adjacency) ||
      %{"incoming" => [], "outgoing" => []}
  end

  defp relation_value(relation) do
    Map.get(relation, "relation") || Map.get(relation, :relation)
  end

  defp relation_type(relation) do
    Map.get(relation, "type") || Map.get(relation, :type) || relation_value(relation)
  end

  defp relation_target_id(relation) do
    Map.get(relation, "target_id") || Map.get(relation, :target_id)
  end

  defp relations(object), do: Map.get(object, "relations") || Map.get(object, :relations) || []

  defp context_id(nil), do: nil
  defp context_id(object), do: Map.get(object, "context_id") || Map.get(object, :context_id)
  defp title(object), do: Map.get(object, "title") || Map.get(object, :title)
  defp body(object), do: Map.get(object, "body") || Map.get(object, :body)

  defp object_type(object) do
    Map.get(object, "object_type") || Map.get(object, :object_type) || "message"
  end

  defp context_objects(snapshot),
    do: Map.get(snapshot, "context_objects") || Map.get(snapshot, :context_objects) || []

  defp contributions(snapshot),
    do: Map.get(snapshot, "contributions") || Map.get(snapshot, :contributions) || []

  defp map_value(map, key) do
    atom_key = Map.get(@map_value_keys, key)
    Map.get(map, key) || maybe_atom_map_value(map, atom_key)
  end

  defp maybe_atom_map_value(_map, nil), do: nil
  defp maybe_atom_map_value(map, atom_key), do: Map.get(map, atom_key)
end
