defmodule JidoHiveServerWeb.RoomRunsController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.RoomRuns
  alias JidoHiveServerWeb.API

  def create(conn, %{"id" => room_id, "data" => attrs}) do
    case RoomRuns.create(room_id, attrs) do
      {:ok, run} ->
        conn
        |> put_status(:accepted)
        |> json(API.data(%{run: run}))

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_room_run", inspect(reason))
    end
  end

  def create(conn, _params) do
    render_error(conn, :unprocessable_entity, "invalid_room_run", "expected data payload")
  end

  def show(conn, %{"id" => room_id, "run_id" => run_id}) do
    case RoomRuns.fetch(room_id, run_id) do
      {:ok, run} ->
        json(conn, API.data(%{run: run}))

      {:error, :room_run_not_found} ->
        render_error(conn, :not_found, "room_run_not_found", "Run not found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_room_run", inspect(reason))
    end
  end

  def delete(conn, %{"id" => room_id, "run_id" => run_id}) do
    case RoomRuns.cancel(room_id, run_id) do
      {:ok, run} ->
        json(conn, API.data(%{run: run}))

      {:error, :room_run_not_found} ->
        render_error(conn, :not_found, "room_run_not_found", "Run not found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "invalid_room_run", inspect(reason))
    end
  end

  defp render_error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(API.error(code, message))
  end
end
