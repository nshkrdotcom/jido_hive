defmodule JidoHiveServerWeb.PoliciesController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.Collaboration.DispatchPolicy.Registry

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Registry.list(), &normalize/1)})
  end

  def show(conn, %{"id" => policy_id_segments}) do
    policy_id =
      case policy_id_segments do
        segments when is_list(segments) -> Enum.join(segments, "/")
        segment when is_binary(segment) -> segment
      end

    case Registry.fetch(policy_id) do
      {:ok, definition} ->
        json(conn, %{data: normalize(definition)})

      {:error, :unknown_policy} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "unknown_policy"})
    end
  end

  defp normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value), do: value
end
