defmodule JidoHiveServer.Collaboration.RoomTimeline do
  @moduledoc false

  alias JidoHiveServer.Collaboration.Schema.RoomEvent

  @schema_version "jido_hive/room_timeline_entry.v1"

  @spec project([RoomEvent.t()], keyword()) :: [map()]
  def project(events, opts \\ []) when is_list(events) and is_list(opts) do
    events
    |> Enum.map(&to_entry/1)
    |> filter_after(Keyword.get(opts, :after))
  end

  @spec next_cursor([map()]) :: String.t() | nil
  def next_cursor([]), do: nil
  def next_cursor(entries), do: entries |> List.last() |> Map.fetch!(:cursor)

  defp filter_after(entries, nil), do: entries

  defp filter_after(entries, cursor) when is_binary(cursor) do
    case Enum.find_index(entries, &(&1.cursor == cursor or &1.event_id == cursor)) do
      nil -> entries
      index -> Enum.drop(entries, index + 1)
    end
  end

  defp filter_after(entries, _other), do: entries

  defp to_entry(%RoomEvent{} = event) do
    payload = normalize(event.payload)
    {kind, title, body, metadata, status} = classify(event.type, payload)

    %{
      entry_id: event.event_id,
      cursor: event.event_id,
      room_id: event.room_id,
      event_id: event.event_id,
      kind: kind,
      title: title,
      body: body,
      assignment_id: metadata["assignment_id"],
      phase: metadata["phase"],
      participant_id: metadata["participant_id"],
      participant_role: metadata["participant_role"],
      target_id: metadata["target_id"],
      status: status,
      schema_version: @schema_version,
      timestamp: DateTime.to_iso8601(event.recorded_at),
      metadata: metadata
    }
  end

  defp classify(:room_created, payload) do
    {"room.created", "Room created", payload["brief"], payload, "completed"}
  end

  defp classify(:assignment_opened, payload) do
    assignment = payload["assignment"] || %{}

    {"assignment.started", "Assignment started", assignment["objective"], assignment, "running"}
  end

  defp classify(:contribution_recorded, payload) do
    contribution = payload["contribution"] || %{}

    {"contribution.recorded", "Contribution recorded", contribution["summary"], contribution,
     contribution["status"] || "completed"}
  end

  defp classify(:assignment_abandoned, payload) do
    {"assignment.abandoned", "Assignment abandoned", payload["reason"], payload, "abandoned"}
  end

  defp classify(:runtime_state_changed, payload) do
    {"room.status.changed", "Room status changed", payload["status"], payload, payload["status"]}
  end

  defp classify(type, payload) do
    type_string = Atom.to_string(type)
    title = type_string |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)

    {String.replace(type_string, "_", "."), title, payload["summary"] || payload["status"],
     payload, payload["status"]}
  end

  defp normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(value), do: value
end
