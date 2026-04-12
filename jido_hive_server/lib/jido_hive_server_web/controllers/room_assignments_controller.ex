defmodule JidoHiveServerWeb.RoomAssignmentsController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.Collaboration
  alias JidoHiveServerWeb.API

  def index(conn, %{"id" => room_id} = params) do
    opts =
      []
      |> maybe_put(:participant_id, params["participant_id"])
      |> maybe_put(:status, params["status"])
      |> maybe_put_integer(:limit, params["limit"])

    case Collaboration.list_assignments(room_id, opts) do
      {:ok, assignments} ->
        json(conn, API.data(assignments))

      {:error, :room_not_found} ->
        render_error(conn, :not_found, "room_not_found", "Room not found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_assignment_query", inspect(reason))
    end
  end

  def update(conn, %{
        "id" => room_id,
        "assignment_id" => assignment_id,
        "data" => %{"status" => status}
      }) do
    case Collaboration.update_assignment(room_id, assignment_id, status) do
      {:ok, snapshot} ->
        assignment = Enum.find(snapshot.assignments, &(&1.id == assignment_id))
        json(conn, API.data(assignment))

      {:error, :room_not_found} ->
        render_error(conn, :not_found, "room_not_found", "Room not found")

      {:error, :assignment_not_found} ->
        render_error(conn, :not_found, "assignment_not_found", "Assignment not found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_assignment_patch", inspect(reason))
    end
  end

  def update(conn, _params) do
    render_error(
      conn,
      :unprocessable_entity,
      "invalid_assignment_patch",
      "expected assignment status payload"
    )
  end

  defp render_error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(API.error(code, message))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_integer(opts, _key, nil), do: opts

  defp maybe_put_integer(opts, key, value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> Keyword.put(opts, key, integer)
      _other -> opts
    end
  end
end
