defmodule JidoHiveServerWeb.RoomContributionsController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.Collaboration
  alias JidoHiveServerWeb.API

  def index(conn, %{"id" => room_id} = params) do
    limit = parse_limit(params["limit"], 50)

    opts =
      []
      |> Keyword.put(:after_sequence, parse_non_neg_integer(params["after_sequence"], 0))
      |> Keyword.put(:limit, limit + 1)
      |> maybe_put(:participant_id, params["participant_id"])
      |> maybe_put(:assignment_id, params["assignment_id"])
      |> maybe_put(:kind, params["kind"])

    case Collaboration.list_contributions(room_id, opts) do
      {:ok, contributions} ->
        {page, has_more} = split_page(contributions, limit)

        next_after_sequence =
          page |> List.last() |> then(&if(&1, do: &1.event_sequence, else: nil))

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
        render_error(conn, :unprocessable_entity, "invalid_contribution_query", inspect(reason))
    end
  end

  def create(conn, %{"id" => room_id, "data" => attrs}) do
    case Collaboration.submit_contribution(room_id, attrs) do
      {:ok, snapshot} ->
        json(conn, API.data(snapshot))

      {:error, :room_not_found} ->
        render_error(conn, :not_found, "room_not_found", "Room not found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_contribution", inspect(reason))
    end
  end

  def create(conn, _params) do
    render_error(conn, :unprocessable_entity, "invalid_contribution", "expected data payload")
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

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp render_error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(API.error(code, message))
  end
end
