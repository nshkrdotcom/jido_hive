defmodule JidoHiveServerWeb.RoomEventsController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.{Collaboration, Persistence}

  def index(conn, %{"id" => room_id}) do
    case Collaboration.fetch_room(room_id) do
      {:ok, _snapshot} ->
        events =
          room_id
          |> Persistence.list_room_events()
          |> Enum.map(&normalize_event/1)

        json(conn, %{data: events})

      {:error, :room_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "room_not_found"})
    end
  end

  defp normalize_event(event) do
    %{
      "event_id" => event.event_id,
      "room_id" => event.room_id,
      "type" => Atom.to_string(event.type),
      "payload" => normalize(event.payload),
      "causation_id" => event.causation_id,
      "correlation_id" => event.correlation_id,
      "recorded_at" => DateTime.to_iso8601(event.recorded_at)
    }
  end

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(%_{} = value), do: value |> Map.from_struct() |> normalize()

  defp normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value), do: value
end
