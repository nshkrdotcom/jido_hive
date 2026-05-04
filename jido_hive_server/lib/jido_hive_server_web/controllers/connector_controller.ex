defmodule JidoHiveServerWeb.ConnectorController do
  use JidoHiveServerWeb, :controller

  alias Jido.Integration.V2
  alias JidoHiveServer.GovernedConnectorAuthority

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
  @governed_start_direct_fields [
    "actor_id",
    "auth_type",
    "profile_id",
    "flow_kind",
    "subject",
    "requested_scopes",
    "metadata",
    "callback_uri",
    "state_token",
    "pkce_verifier_digest",
    "connection_id",
    "management_mode",
    "secret_source",
    "external_secret_ref",
    "environment",
    "granted_scopes",
    "secret",
    "lease_fields",
    "source",
    "source_ref"
  ]
  @governed_complete_direct_fields [
    "actor_id",
    "auth_type",
    "profile_id",
    "flow_kind",
    "subject",
    "requested_scopes",
    "metadata",
    "callback_uri",
    "state_token",
    "pkce_verifier_digest",
    "connection_id",
    "management_mode",
    "secret_source",
    "external_secret_ref",
    "environment",
    "granted_scopes",
    "secret",
    "lease_fields",
    "expires_at",
    "refresh_token_expires_at",
    "callback_received_at",
    "source",
    "source_ref",
    "reason"
  ]

  @atom_values %{
    auth_type: %{
      "api_key" => :api_key,
      "none" => :none,
      "oauth" => :oauth,
      "oauth2" => :oauth2,
      "token" => :token
    },
    environment: %{
      "dev" => :dev,
      "local" => :local,
      "prod" => :prod,
      "production" => :prod,
      "test" => :test
    },
    flow_kind: %{
      "browser" => :browser,
      "device" => :device,
      "manual" => :manual,
      "oauth" => :oauth,
      "oauth2" => :oauth2
    },
    management_mode: %{
      "external" => :external,
      "managed" => :managed,
      "manual" => :manual,
      "operator" => :operator
    },
    secret_source: %{
      "external" => :external,
      "inline" => :inline,
      "manual" => :manual,
      "operator" => :operator,
      "operator_input" => :operator_input
    },
    source: %{
      "callback" => :callback,
      "manual" => :manual,
      "operator" => :operator,
      "operator_input" => :operator_input,
      "server" => :server
    }
  }

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
      |> maybe_infer_requested_scopes(connector_id)

    with {:ok, attrs} <- apply_governed_start(connector_id, tenant_id, params, attrs),
         {:ok, result} <- V2.start_install(connector_id, tenant_id, attrs) do
      json(conn, %{data: normalize(result)})
    else
      {:error, reason} -> render_error(conn, :unprocessable_entity, reason)
    end
  end

  def complete_install(conn, %{"install_id" => install_id} = params) do
    attrs =
      params
      |> Map.drop(["install_id"])
      |> normalize_install_attrs()
      |> maybe_infer_granted_scopes(install_id)

    with {:ok, attrs} <- apply_governed_complete(install_id, params, attrs),
         {:ok, result} <- V2.complete_install(install_id, attrs) do
      json(conn, %{data: normalize(result)})
    else
      {:error, reason} -> render_error(conn, :unprocessable_entity, reason)
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
    @atom_values
    |> Map.fetch!(key)
    |> Map.get(value, value)
  end

  defp normalize_install_value(key, value)
       when key in @datetime_value_keys and is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> value
    end
  end

  defp normalize_install_value(_key, value), do: value

  defp maybe_infer_requested_scopes(attrs, connector_id) do
    case Map.get(attrs, :requested_scopes) do
      scopes when is_list(scopes) and scopes != [] ->
        attrs

      _other ->
        put_scopes_if_present(attrs, :requested_scopes, connector_requested_scopes(connector_id))
    end
  end

  defp maybe_infer_granted_scopes(attrs, install_id) do
    case Map.get(attrs, :granted_scopes) do
      scopes when is_list(scopes) and scopes != [] ->
        attrs

      _other ->
        install_requested_scopes(install_id)
        |> case do
          [] ->
            attrs

          scopes ->
            Map.put(attrs, :granted_scopes, scopes)
        end
    end
  end

  defp install_requested_scopes(install_id) do
    case V2.fetch_install(install_id) do
      {:ok, %{requested_scopes: scopes}} when is_list(scopes) and scopes != [] ->
        scopes

      {:ok, %{connector_id: connector_id}} ->
        connector_requested_scopes(connector_id)

      _other ->
        []
    end
  end

  defp connector_requested_scopes(connector_id) do
    case V2.fetch_connector(connector_id) do
      {:ok, %{auth: %{requested_scopes: scopes}}} when is_list(scopes) and scopes != [] ->
        scopes

      _other ->
        []
    end
  end

  defp put_scopes_if_present(attrs, _key, []), do: attrs
  defp put_scopes_if_present(attrs, key, scopes), do: Map.put(attrs, key, scopes)

  defp apply_governed_start(connector_id, tenant_id, params, attrs) do
    case Map.get(params, "governed_authority") do
      nil ->
        {:ok, attrs}

      authority_attrs when is_map(authority_attrs) ->
        with :ok <- reject_governed_direct_fields(params, @governed_start_direct_fields),
             authority_attrs <-
               authority_attrs
               |> Map.put_new("connector_id", connector_id)
               |> Map.put_new("tenant_id", tenant_id),
             {:ok, authority} <- GovernedConnectorAuthority.new(authority_attrs),
             :ok <-
               ensure_governed_route_match(authority.connector_id, connector_id, :connector_id),
             :ok <- ensure_governed_route_match(authority.tenant_id, tenant_id, :tenant_id) do
          {:ok, GovernedConnectorAuthority.start_attrs(authority)}
        end

      _other ->
        {:error, :invalid_governed_connector_authority}
    end
  end

  defp apply_governed_complete(install_id, params, attrs) do
    case Map.get(params, "governed_authority") do
      nil ->
        {:ok, attrs}

      authority_attrs when is_map(authority_attrs) ->
        with :ok <- reject_governed_direct_fields(params, @governed_complete_direct_fields),
             {:ok, install} <- V2.fetch_install(install_id),
             authority_attrs <-
               authority_attrs
               |> Map.put_new("connector_id", install.connector_id)
               |> Map.put_new("tenant_id", install.tenant_id),
             {:ok, authority} <- GovernedConnectorAuthority.new(authority_attrs),
             :ok <-
               ensure_governed_route_match(
                 authority.connector_id,
                 install.connector_id,
                 :connector_id
               ),
             :ok <-
               ensure_governed_route_match(authority.tenant_id, install.tenant_id, :tenant_id) do
          {:ok, GovernedConnectorAuthority.complete_attrs(authority)}
        end

      _other ->
        {:error, :invalid_governed_connector_authority}
    end
  end

  defp reject_governed_direct_fields(params, fields) do
    case Enum.find(fields, &Map.has_key?(params, &1)) do
      nil -> :ok
      field -> {:error, {:governed_direct_connector_field, field}}
    end
  end

  defp ensure_governed_route_match(value, value, _field), do: :ok

  defp ensure_governed_route_match(_authority_value, _route_value, field) do
    {:error, {:governed_connector_route_mismatch, field}}
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
