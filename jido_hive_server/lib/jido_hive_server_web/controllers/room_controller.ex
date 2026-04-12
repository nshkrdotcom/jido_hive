defmodule JidoHiveServerWeb.RoomController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.Collaboration
  alias JidoHiveServer.RoomRuns
  alias JidoHiveServerWeb.API

  def index(conn, params) do
    opts =
      []
      |> maybe_put(:participant_id, params["participant_id"])
      |> maybe_put(:status, params["status"])
      |> maybe_put_integer(:limit, params["limit"])

    case Collaboration.list_rooms(opts) do
      {:ok, snapshots} ->
        json(conn, API.data(Enum.map(snapshots, &room_resource/1)))

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_room_query", inspect(reason))
    end
  end

  def create(conn, %{"data" => attrs}) do
    case Collaboration.create_room(attrs) do
      {:ok, snapshot} ->
        conn
        |> put_status(:created)
        |> json(API.data(room_resource(snapshot)))

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_room", inspect(reason))
    end
  end

  def create(conn, _params) do
    render_error(conn, :unprocessable_entity, "invalid_room", "expected data payload")
  end

  def show(conn, %{"id" => room_id}) do
    case Collaboration.fetch_room_snapshot(room_id) do
      {:ok, snapshot} ->
        json(conn, API.data(room_resource(snapshot)))

      {:error, :room_not_found} ->
        render_error(conn, :not_found, "room_not_found", "Room not found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_room", inspect(reason))
    end
  end

  def patch(conn, %{"id" => room_id, "data" => attrs}) do
    case Collaboration.patch_room(room_id, attrs) do
      {:ok, snapshot} ->
        json(conn, API.data(room_resource(snapshot)))

      {:error, :room_not_found} ->
        render_error(conn, :not_found, "room_not_found", "Room not found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_room_patch", inspect(reason))
    end
  end

  def patch(conn, _params) do
    render_error(conn, :unprocessable_entity, "invalid_room_patch", "expected data payload")
  end

  def delete(conn, %{"id" => room_id}) do
    case Collaboration.close_room(room_id) do
      {:ok, snapshot} ->
        :ok = RoomRuns.cancel_active_for_room(room_id)
        json(conn, API.data(room_resource(snapshot)))

      {:error, :room_not_found} ->
        render_error(conn, :not_found, "room_not_found", "Room not found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_room_patch", inspect(reason))
    end
  end

  defp room_resource(snapshot) do
    %{
      room: snapshot.room,
      participants: snapshot.participants,
      assignment_counts: assignment_counts(snapshot),
      contribution_count: contribution_count(snapshot)
    }
  end

  defp assignment_counts(snapshot) do
    Enum.reduce(
      snapshot.assignments,
      %{"pending" => 0, "active" => 0, "completed" => 0, "expired" => 0},
      fn assignment, acc ->
        Map.update(acc, assignment.status, 1, &(&1 + 1))
      end
    )
  end

  defp contribution_count(snapshot), do: length(snapshot.contributions)

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
