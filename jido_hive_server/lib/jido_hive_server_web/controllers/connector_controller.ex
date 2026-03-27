defmodule JidoHiveServerWeb.ConnectorController do
  use JidoHiveServerWeb, :controller

  alias Jido.Integration.V2

  def connections(conn, %{"connector_id" => connector_id} = params) do
    filters =
      %{}
      |> maybe_put(:connector_id, connector_id)
      |> maybe_put(:tenant_id, params["tenant_id"])
      |> maybe_put(:actor_id, params["actor_id"])
      |> maybe_put(:subject, params["subject"])

    json(conn, %{data: Enum.map(V2.connections(filters), &normalize/1)})
  end

  def start_install(conn, %{"connector_id" => connector_id, "tenant_id" => tenant_id} = params) do
    attrs =
      params
      |> Map.drop(["connector_id", "tenant_id"])
      |> normalize_install_attrs()

    case V2.start_install(connector_id, tenant_id, attrs) do
      {:ok, result} ->
        json(conn, %{data: normalize(result)})

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, reason)
    end
  end

  def complete_install(conn, %{"install_id" => install_id} = params) do
    attrs =
      params
      |> Map.drop(["install_id"])
      |> normalize_install_attrs()

    case V2.complete_install(install_id, attrs) do
      {:ok, result} ->
        json(conn, %{data: normalize(result)})

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, reason)
    end
  end

  def show_install(conn, %{"install_id" => install_id}) do
    case V2.fetch_install(install_id) do
      {:ok, install} ->
        json(conn, %{data: normalize(install)})

      {:error, :unknown_install} ->
        render_error(conn, :not_found, :unknown_install)
    end
  end

  defp normalize_install_attrs(attrs) do
    attrs
    |> maybe_atomize_key("auth_type")
    |> maybe_atomize_key("environment")
  end

  defp maybe_atomize_key(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) -> Map.put(attrs, key, String.to_atom(value))
      _other -> attrs
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(%_{} = struct), do: struct |> Map.from_struct() |> normalize()

  defp normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value), do: value

  defp render_error(conn, status, reason) do
    conn
    |> put_status(status)
    |> json(%{error: inspect(reason)})
  end
end
