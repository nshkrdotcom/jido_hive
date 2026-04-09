defmodule JidoHiveServerWeb.RoomController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.Collaboration
  alias JidoHiveServer.RunOperations

  def create(conn, params) do
    case Collaboration.create_room(params) do
      {:ok, snapshot} ->
        conn
        |> put_status(:created)
        |> json(%{data: normalize(snapshot)})

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, reason)
    end
  end

  def show(conn, %{"id" => room_id}) do
    case Collaboration.fetch_room(room_id) do
      {:ok, snapshot} ->
        json(conn, %{data: normalize(snapshot)})

      {:error, :room_not_found} ->
        render_error(conn, :not_found, :room_not_found)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, reason)
    end
  end

  def run_first_slice(conn, %{"id" => room_id}) do
    case Collaboration.run_first_slice(room_id) do
      {:ok, snapshot} ->
        json(conn, %{data: normalize(snapshot)})

      {:error, :room_not_found} ->
        render_error(conn, :not_found, :room_not_found)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, reason)
    end
  end

  def start_run_operation(conn, %{"id" => room_id} = params) do
    max_assignments = parse_optional_integer(Map.get(params, "max_assignments"))

    assignment_timeout_ms =
      parse_integer(Map.get(params, "assignment_timeout_ms", 180_000), 180_000)

    run_opts =
      [assignment_timeout_ms: assignment_timeout_ms]
      |> maybe_put_max_assignments(max_assignments)

    case RunOperations.start_run(room_id, run_opts) do
      {:ok, operation} ->
        conn
        |> put_status(:accepted)
        |> json(%{data: normalize(operation)})

      {:error, :room_not_found} ->
        render_error(conn, :not_found, :room_not_found)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, reason)
    end
  end

  def show_run_operation(conn, %{"id" => room_id, "operation_id" => operation_id}) do
    case RunOperations.fetch(room_id, operation_id) do
      {:ok, operation} ->
        json(conn, %{data: normalize(operation)})

      {:error, :operation_not_found} ->
        render_error(conn, :not_found, :operation_not_found)

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

  defp render_error(conn, status, reason) when is_atom(reason) do
    conn
    |> put_status(status)
    |> json(%{error: Atom.to_string(reason)})
  end

  defp render_error(conn, status, reason) do
    conn
    |> put_status(status)
    |> json(%{error: inspect(reason)})
  end

  defp parse_integer(value, _default) when is_integer(value), do: value

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _other -> default
    end
  end

  defp parse_integer(_value, default), do: default

  defp parse_optional_integer(nil), do: nil
  defp parse_optional_integer(value) when is_integer(value), do: value
  defp parse_optional_integer(value) when is_binary(value), do: parse_integer(value, nil)
  defp parse_optional_integer(_value), do: nil

  defp maybe_put_max_assignments(opts, nil), do: opts

  defp maybe_put_max_assignments(opts, max_assignments),
    do: Keyword.put(opts, :max_assignments, max_assignments)

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(%_{} = value), do: value |> Map.from_struct() |> normalize()

  defp normalize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value), do: value
end
