defmodule JidoHiveServerWeb.RoomParticipantsController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.Collaboration
  alias JidoHiveServerWeb.API

  def index(conn, %{"id" => room_id}) do
    case Collaboration.list_participants(room_id) do
      {:ok, participants} ->
        json(conn, API.data(participants))

      {:error, :room_not_found} ->
        render_error(conn, :not_found, "room_not_found", "Room not found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_participant_query", inspect(reason))
    end
  end

  def create(conn, %{"id" => room_id, "data" => attrs}) do
    case Collaboration.upsert_participant(room_id, attrs) do
      {:ok, snapshot} ->
        json(conn, API.data(snapshot.participants))

      {:error, :room_not_found} ->
        render_error(conn, :not_found, "room_not_found", "Room not found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_participant", inspect(reason))
    end
  end

  def create(conn, _params) do
    render_error(conn, :unprocessable_entity, "invalid_participant", "expected data payload")
  end

  def delete(conn, %{"id" => room_id, "participant_id" => participant_id}) do
    case Collaboration.remove_participant(room_id, participant_id) do
      {:ok, snapshot} ->
        json(conn, API.data(snapshot.participants))

      {:error, :room_not_found} ->
        render_error(conn, :not_found, "room_not_found", "Room not found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_participant", inspect(reason))
    end
  end

  defp render_error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(API.error(code, message))
  end
end
