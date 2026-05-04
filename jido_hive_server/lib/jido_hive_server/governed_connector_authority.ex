defmodule JidoHiveServer.GovernedConnectorAuthority do
  @moduledoc false

  defstruct authority_ref: nil,
            connector_id: nil,
            tenant_id: nil,
            actor_id: nil,
            subject: nil,
            credential_ref: nil,
            secret_ref: nil,
            auth_type: :oauth2,
            environment: :prod,
            requested_scopes: [],
            granted_scopes: [],
            redaction_values: []

  @type t :: %__MODULE__{}

  @auth_types %{
    "api_key" => :api_key,
    "none" => :none,
    "oauth" => :oauth,
    "oauth2" => :oauth2,
    "token" => :token
  }
  @environments %{
    "dev" => :dev,
    "local" => :local,
    "prod" => :prod,
    "production" => :prod,
    "test" => :test
  }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, authority_ref} <- required_binary(attrs, "authority_ref"),
         {:ok, connector_id} <- required_binary(attrs, "connector_id"),
         {:ok, tenant_id} <- required_binary(attrs, "tenant_id"),
         {:ok, actor_id} <- required_binary(attrs, "actor_id"),
         {:ok, subject} <- required_binary(attrs, "subject"),
         {:ok, credential_ref} <- required_binary(attrs, "credential_ref"),
         {:ok, secret_ref} <- required_binary(attrs, "secret_ref"),
         {:ok, auth_type} <- enum(attrs, "auth_type", @auth_types, :oauth2),
         {:ok, environment} <- enum(attrs, "environment", @environments, :prod) do
      {:ok,
       %__MODULE__{
         authority_ref: authority_ref,
         connector_id: connector_id,
         tenant_id: tenant_id,
         actor_id: actor_id,
         subject: subject,
         credential_ref: credential_ref,
         secret_ref: secret_ref,
         auth_type: auth_type,
         environment: environment,
         requested_scopes: string_list(Map.get(attrs, "requested_scopes", [])),
         granted_scopes: string_list(Map.get(attrs, "granted_scopes", [])),
         redaction_values: string_list(Map.get(attrs, "redaction_values", []))
       }}
    end
  end

  @spec start_attrs(t()) :: map()
  def start_attrs(%__MODULE__{} = authority) do
    %{
      actor_id: authority.actor_id,
      auth_type: authority.auth_type,
      subject: authority.subject,
      requested_scopes: authority.requested_scopes,
      secret_source: :external,
      external_secret_ref: authority.secret_ref,
      environment: authority.environment,
      metadata: ref_metadata(authority)
    }
  end

  @spec complete_attrs(t()) :: map()
  def complete_attrs(%__MODULE__{} = authority) do
    %{
      actor_id: authority.actor_id,
      subject: authority.subject,
      granted_scopes: authority.granted_scopes,
      secret_source: :external,
      external_secret_ref: authority.secret_ref,
      source: :operator,
      source_ref: ref_metadata(authority),
      metadata: ref_metadata(authority)
    }
  end

  defp ref_metadata(%__MODULE__{} = authority) do
    %{
      "authority_ref" => authority.authority_ref,
      "credential_ref" => authority.credential_ref,
      "external_secret_ref" => authority.secret_ref
    }
  end

  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp required_binary(attrs, key) do
    case optional_binary(attrs, key) do
      nil -> {:error, {:missing_governed_connector_field, key}}
      value -> {:ok, value}
    end
  end

  defp optional_binary(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp enum(attrs, key, values, default) do
    case Map.get(attrs, key) do
      nil ->
        {:ok, default}

      value when is_atom(value) ->
        if value in Map.values(values) do
          {:ok, value}
        else
          {:error, {:invalid_governed_connector_field, key}}
        end

      value when is_binary(value) ->
        case Map.fetch(values, String.downcase(String.trim(value))) do
          {:ok, atom} -> {:ok, atom}
          :error -> {:error, {:invalid_governed_connector_field, key}}
        end

      _other ->
        {:error, {:invalid_governed_connector_field, key}}
    end
  end

  defp string_list(values) when is_list(values) do
    Enum.filter(values, fn value -> is_binary(value) and value != "" end)
  end

  defp string_list(_other), do: []
end
