defmodule JidoHiveClient.RoomWorkflow do
  @moduledoc """
  Shared workflow-contract helpers for headless tools and interactive clients.

  The server is the canonical source of workflow meaning. This module normalizes
  the server contract and provides conservative fallbacks when older snapshots do
  not yet include `workflow_summary`.
  """

  @type summary :: %{
          objective: String.t(),
          stage: String.t(),
          next_action: String.t(),
          blockers: [map()],
          publish_ready: boolean(),
          publish_blockers: [String.t()],
          graph_counts: map(),
          focus_candidates: [map()]
        }

  @spec summary(map()) :: summary()
  def summary(snapshot) when is_map(snapshot) do
    case value(snapshot, "workflow_summary") do
      %{} = workflow_summary ->
        normalize_summary(workflow_summary, snapshot)

      _other ->
        default_summary(snapshot)
    end
  end

  def summary(_snapshot), do: default_summary(%{})

  @spec inspect_sync(%{
          required(:room_snapshot) => map(),
          required(:entries) => [map()],
          required(:context_objects) => [map()],
          required(:operations) => [map()],
          required(:next_cursor) => String.t() | nil
        }) :: map()
  def inspect_sync(%{
        room_snapshot: room_snapshot,
        entries: entries,
        context_objects: context_objects,
        operations: operations,
        next_cursor: next_cursor
      })
      when is_map(room_snapshot) and is_list(entries) and is_list(context_objects) and
             is_list(operations) do
    workflow_summary = summary(room_snapshot)

    %{
      room_id: value(room_snapshot, "room_id"),
      status: value(room_snapshot, "status") || "idle",
      workflow_summary: workflow_summary,
      room: room_snapshot,
      entries: entries,
      context_objects: context_objects,
      operations: operations,
      next_cursor: next_cursor
    }
  end

  def inspect_sync(_sync_result) do
    %{
      room_id: nil,
      status: "unknown",
      workflow_summary: default_summary(%{}),
      room: %{},
      entries: [],
      context_objects: [],
      operations: [],
      next_cursor: nil
    }
  end

  defp normalize_summary(workflow_summary, snapshot) do
    %{
      objective:
        value(workflow_summary, "objective") || value(snapshot, "brief") ||
          "No room objective available",
      stage:
        value(workflow_summary, "stage") || humanize_status(value(snapshot, "status") || "idle"),
      next_action: value(workflow_summary, "next_action") || "Refresh room data",
      blockers: normalize_blockers(value(workflow_summary, "blockers")),
      publish_ready:
        case value(workflow_summary, "publish_ready") do
          true -> true
          false -> false
          _other -> value(snapshot, "status") == "publication_ready"
        end,
      publish_blockers: normalize_strings(value(workflow_summary, "publish_blockers")),
      graph_counts: normalize_map(value(workflow_summary, "graph_counts")),
      focus_candidates: normalize_list_of_maps(value(workflow_summary, "focus_candidates"))
    }
  end

  defp default_summary(snapshot) do
    publish_ready = value(snapshot, "status") == "publication_ready"

    %{
      objective: value(snapshot, "brief") || "No room objective available",
      stage: humanize_status(value(snapshot, "status") || "unavailable"),
      next_action: "Refresh room data",
      blockers: [],
      publish_ready: publish_ready,
      publish_blockers: if(publish_ready, do: [], else: ["Server workflow summary unavailable"]),
      graph_counts: %{
        total: length(normalize_list(value(snapshot, "context_objects"))),
        decisions: 0,
        questions: 0,
        contradictions: 0,
        duplicate_groups: 0,
        duplicates: 0,
        stale: 0
      },
      focus_candidates: []
    }
  end

  defp normalize_blockers(blockers) when is_list(blockers) do
    Enum.map(blockers, &normalize_map/1)
  end

  defp normalize_blockers(_blockers), do: []

  defp normalize_strings(values) when is_list(values) do
    Enum.filter(values, &is_binary/1)
  end

  defp normalize_strings(_values), do: []

  defp normalize_list_of_maps(values) when is_list(values) do
    Enum.map(values, &normalize_map/1)
  end

  defp normalize_list_of_maps(_values), do: []

  defp normalize_list(values) when is_list(values), do: values
  defp normalize_list(_values), do: []

  defp normalize_map(values) when is_map(values) do
    Map.new(values, fn {key, value} -> {normalize_key(key), normalize_value(value)} end)
  end

  defp normalize_map(_values), do: %{}

  defp normalize_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    case existing_atom_key(key) do
      nil -> key
      atom_key -> atom_key
    end
  end

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp humanize_status(status) when is_binary(status) do
    status
    |> String.replace("_", " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
