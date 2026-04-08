defmodule JidoHiveServerWeb.ConnectorController do
  use JidoHiveServerWeb, :controller

  alias Jido.Integration.V2

  @install_attr_keys %{
    "actor_id" => :actor_id,
    "auth_type" => :auth_type,
    "profile_id" => :profile_id,
    "flow_kind" => :flow_kind,
    "subject" => :subject,
    "requested_scopes" => :requested_scopes,
    "metadata" => :metadata,
    "now" => :now,
    "callback_uri" => :callback_uri,
    "state_token" => :state_token,
    "pkce_verifier_digest" => :pkce_verifier_digest,
    "install_ttl_seconds" => :install_ttl_seconds,
    "connection_id" => :connection_id,
    "management_mode" => :management_mode,
    "secret_source" => :secret_source,
    "external_secret_ref" => :external_secret_ref,
    "environment" => :environment,
    "granted_scopes" => :granted_scopes,
    "secret" => :secret,
    "lease_fields" => :lease_fields,
    "expires_at" => :expires_at,
    "refresh_token_expires_at" => :refresh_token_expires_at,
    "callback_received_at" => :callback_received_at,
    "source" => :source,
    "source_ref" => :source_ref,
    "reason" => :reason
  }

  @atom_value_keys [
    :auth_type,
    :environment,
    :flow_kind,
    :management_mode,
    :secret_source,
    :source
  ]
  @datetime_value_keys [:now, :expires_at, :refresh_token_expires_at, :callback_received_at]

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
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      normalized_key = Map.get(@install_attr_keys, key, key)
      Map.put(acc, normalized_key, normalize_install_value(normalized_key, value))
    end)
  end

  defp normalize_install_value(key, value)

  defp normalize_install_value(key, value) when key in @atom_value_keys and is_binary(value) do
    String.to_atom(value)
  end

  defp normalize_install_value(key, value)
       when key in @datetime_value_keys and is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> value
    end
  end

  defp normalize_install_value(_key, value), do: value

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
