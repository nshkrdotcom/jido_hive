defmodule JidoHiveServerWeb.RoomEventsController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.Collaboration
  alias JidoHiveServerWeb.API

  def index(conn, %{"id" => room_id} = params) do
    limit = parse_limit(params["limit"], 100)
    after_sequence = parse_non_neg_integer(params["after"], 0)

    case Collaboration.list_events(room_id, after_sequence: after_sequence, limit: limit + 1) do
      {:ok, events} ->
        {page, has_more} = split_page(events, limit)
        next_after_sequence = page |> List.last() |> then(&if(&1, do: &1.sequence, else: nil))

        json(
          conn,
          API.data(page, %{
            next_after_sequence: next_after_sequence,
            has_more: has_more
          })
        )

      {:error, :room_not_found} ->
        render_error(conn, :not_found, "room_not_found", "Room not found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_event_query", inspect(reason))
    end
  end

  defp split_page(list, limit) do
    if length(list) > limit do
      {Enum.take(list, limit), true}
    else
      {list, false}
    end
  end

  defp parse_limit(nil, default), do: default

  defp parse_limit(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _other -> default
    end
  end

  defp parse_non_neg_integer(nil, default), do: default

  defp parse_non_neg_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _other -> default
    end
  end

  defp render_error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(API.error(code, message))
  end
end
