defmodule JidoHiveServerWeb.RoomContributionController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.Collaboration

  def create(conn, %{"id" => room_id} = params) do
    attrs = Map.delete(params, "id")

    case Collaboration.record_manual_contribution(room_id, attrs) do
      {:ok, snapshot} ->
        conn
        |> put_status(:created)
        |> json(%{data: normalize(snapshot)})

      {:error, :room_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "room_not_found"})

      {:error, reason} when is_atom(reason) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: Atom.to_string(reason)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp normalize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value), do: value
end
