defmodule JidoHiveServerWeb.RoomContextController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.Collaboration

  def index(conn, %{"id" => room_id}) do
    case Collaboration.list_context_objects(room_id) do
      {:ok, context_objects} ->
        json(conn, %{data: Enum.map(context_objects, &normalize/1)})

      {:error, :room_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "room_not_found"})
    end
  end

  def show(conn, %{"id" => room_id, "context_id" => context_id}) do
    case Collaboration.fetch_context_object(room_id, context_id) do
      {:ok, context_object} ->
        json(conn, %{data: normalize(context_object)})

      {:error, :room_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "room_not_found"})

      {:error, :context_object_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "context_object_not_found"})
    end
  end

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(%_{} = value), do: value |> Map.from_struct() |> normalize()

  defp normalize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value), do: value
end
