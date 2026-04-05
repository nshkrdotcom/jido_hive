defmodule JidoHiveServerWeb.WorkflowsController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.Collaboration.Workflow.Registry

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Registry.list(), &normalize/1)})
  end

  def show(conn, %{"id" => workflow_id_segments}) do
    workflow_id =
      case workflow_id_segments do
        segments when is_list(segments) -> Enum.join(segments, "/")
        segment when is_binary(segment) -> segment
      end

    case Registry.fetch(workflow_id) do
      {:ok, definition} ->
        json(conn, %{data: normalize(definition)})

      {:error, :unknown_workflow} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "unknown_workflow"})
    end
  end

  defp normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value), do: value
end
