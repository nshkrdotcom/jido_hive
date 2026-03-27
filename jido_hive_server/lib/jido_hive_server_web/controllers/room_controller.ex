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

  def run(conn, %{"id" => room_id} = params) do
    max_turns =
      params
      |> Map.get("max_turns", 6)
      |> parse_integer(6)

    turn_timeout_ms =
      params
      |> Map.get("turn_timeout_ms", 180_000)
      |> parse_integer(180_000)

    case Collaboration.run_room(room_id,
           max_turns: max_turns,
           turn_timeout_ms: turn_timeout_ms
         ) do
      {:ok, snapshot} ->
        json(conn, %{data: snapshot})

      {:error, :room_not_found} ->
        render_error(conn, :not_found, :room_not_found)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, reason)
    end
  end

  def publication_plan(conn, %{"id" => room_id}) do
    case Collaboration.publication_plan(room_id) do
      {:ok, plan} ->
        json(conn, %{data: plan})

      {:error, :room_not_found} ->
        render_error(conn, :not_found, :room_not_found)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, reason)
    end
  end

  def publication_runs(conn, %{"id" => room_id}) do
    case Collaboration.publication_runs(room_id) do
      {:ok, runs} ->
        json(conn, %{data: runs})

      {:error, :room_not_found} ->
        render_error(conn, :not_found, :room_not_found)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, reason)
    end
  end

  def execute_publications(conn, %{"id" => room_id} = params) do
    case Collaboration.execute_publications(room_id, Map.delete(params, "id")) do
      {:ok, result} ->
        json(conn, %{data: result})

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

  defp parse_integer(value, _default) when is_integer(value), do: value

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _other -> default
    end
  end

  defp parse_integer(_value, default), do: default
end
