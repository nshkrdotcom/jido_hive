defmodule JidoHiveServer.Collaboration.RoomTimeline do
  @moduledoc false

  alias JidoHiveServer.Collaboration.Schema.RoomEvent

  @schema_version "jido_hive/room_timeline_entry.v1"

  @spec project([RoomEvent.t()], keyword()) :: [map()]
  def project(events, opts \\ []) when is_list(events) and is_list(opts) do
    entries =
      events
      |> Enum.map(&to_entry/1)
      |> filter_after(Keyword.get(opts, :after))

    entries
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
    {kind, title, body, status} = classify(event.type, payload)

    %{
      entry_id: event.event_id,
      cursor: event.event_id,
      room_id: event.room_id,
      event_id: event.event_id,
      kind: kind,
      title: title,
      body: body,
      phase: payload["phase"],
      participant_id: payload["participant_id"],
      participant_role: payload["participant_role"],
      target_id: payload["target_id"],
      job_id: payload["job_id"],
      status: status || payload["status"],
      schema_version: @schema_version,
      timestamp: DateTime.to_iso8601(event.recorded_at),
      metadata: payload
    }
  end

  defp classify(:room_created, payload) do
    {"room.created", "Room created", payload["brief"], "completed"}
  end

  defp classify(:turn_opened, payload) do
    title =
      case payload["phase"] do
        phase when is_binary(phase) and phase != "" ->
          "#{String.capitalize(phase)} turn dispatched"

        _other ->
          "Turn dispatched"
      end

    {"turn.dispatched", title, payload["objective"], "running"}
  end

  defp classify(:turn_completed, payload) do
    {"turn.completed", "Turn completed", payload["summary"], payload["status"] || "completed"}
  end

  defp classify(:turn_failed, payload) do
    {"turn.failed", "Turn failed", payload["summary"] || payload["reason"],
     payload["status"] || "failed"}
  end

  defp classify(:turn_abandoned, payload) do
    {"turn.failed", "Turn abandoned", payload["reason"], "abandoned"}
  end

  defp classify(type, payload) do
    type_string = Atom.to_string(type)

    title =
      type_string
      |> String.split("_")
      |> Enum.map_join(" ", &String.capitalize/1)

    {String.replace(type_string, "_", "."), title, payload["summary"] || payload["reason"],
     payload["status"]}
  end

  defp normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(value), do: value
end
