defmodule JidoHiveServerWeb.RoomController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.Collaboration

  def create(conn, params) do
    case Collaboration.create_room(params) do
      {:ok, snapshot} ->
        conn
        |> put_status(:created)
        |> json(%{data: snapshot})

      {:error, {:already_started, _pid}} ->
        render_error(conn, :conflict, :room_already_started)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, reason)
    end
  end

  def show(conn, %{"id" => room_id}) do
    case Collaboration.fetch_room(room_id) do
      {:ok, snapshot} ->
        json(conn, %{data: snapshot})

      {:error, :room_not_found} ->
        render_error(conn, :not_found, :room_not_found)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, reason)
    end
  end

  def run_first_slice(conn, %{"id" => room_id}) do
    case Collaboration.run_first_slice(room_id) do
      {:ok, snapshot} ->
        json(conn, %{data: snapshot})

      {:error, :room_not_found} ->
        render_error(conn, :not_found, :room_not_found)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, reason)
    end
  end

  defp render_error(conn, status, reason) do
    conn
    |> put_status(status)
    |> json(%{error: Atom.to_string(reason)})
  end
end
