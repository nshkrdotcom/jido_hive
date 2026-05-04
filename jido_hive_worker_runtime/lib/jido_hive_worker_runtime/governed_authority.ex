defmodule JidoHiveWorkerRuntime.GovernedAuthority do
  @moduledoc false

  defstruct authority_ref: nil,
            worker_ref: nil,
            credential_ref: nil,
            provider: :codex,
            model: nil,
            reasoning_effort: :low,
            runtime_id: :asm,
            workspace_id: "workspace-local",
            user_id: "user-local",
            participant_id: "participant-local",
            participant_role: "worker",
            target_id: "target-local",
            capability_id: "workspace.exec.session",
            workspace_root: nil,
            url: "ws://127.0.0.1:4000/socket/websocket",
            api_base_url: nil,
            control_host: "127.0.0.1",
            control_port: nil,
            redaction_values: []

  @type t :: %__MODULE__{}

  @provider_values %{
    "amp" => :amp,
    "claude" => :claude,
    "codex" => :codex,
    "gemini" => :gemini,
    "mock" => :mock,
    "scripted" => :scripted
  }
  @reasoning_efforts %{
    "low" => :low,
    "medium" => :medium,
    "high" => :high,
    "xhigh" => :xhigh
  }
  @runtime_values %{"asm" => :asm}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, refs} <- required_refs(attrs),
         {:ok, values} <- normalized_values(attrs) do
      {:ok, struct!(__MODULE__, Map.merge(refs, values))}
    end
  end

  @spec worker_opts(t()) :: keyword()
  def worker_opts(%__MODULE__{} = authority) do
    [
      url: authority.url,
      api_base_url: authority.api_base_url,
      room_ids: [],
      workspace_id: authority.workspace_id,
      user_id: authority.user_id,
      participant_id: authority.participant_id,
      participant_role: authority.participant_role,
      target_id: authority.target_id,
      capability_id: authority.capability_id,
      workspace_root: authority.workspace_root,
      runtime_id: authority.runtime_id,
      control_port: authority.control_port,
      control_host: authority.control_host,
      runtime: JidoHiveWorkerRuntime.Runtime,
      governed_authority_ref: authority.authority_ref,
      credential_ref: authority.credential_ref,
      redaction_values: authority.redaction_values,
      executor:
        {JidoHiveWorkerRuntime.Executor.Session,
         [
           provider: authority.provider,
           model: authority.model,
           reasoning_effort: authority.reasoning_effort,
           credential_ref: authority.credential_ref,
           authority_ref: authority.authority_ref
         ]}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp required_refs(attrs) do
    with {:ok, authority_ref} <- required_binary(attrs, "authority_ref"),
         {:ok, worker_ref} <- required_binary(attrs, "worker_ref"),
         {:ok, credential_ref} <- required_binary(attrs, "credential_ref") do
      {:ok,
       %{authority_ref: authority_ref, worker_ref: worker_ref, credential_ref: credential_ref}}
    end
  end

  defp normalized_values(attrs) do
    with {:ok, provider} <- enum(attrs, "provider", @provider_values, :codex),
         {:ok, reasoning_effort} <- enum(attrs, "reasoning_effort", @reasoning_efforts, :low),
         {:ok, runtime_id} <- enum(attrs, "runtime_id", @runtime_values, :asm),
         {:ok, control_port} <- optional_positive_integer(attrs, "control_port") do
      {:ok, value_map(attrs, provider, reasoning_effort, runtime_id, control_port)}
    end
  end

  defp value_map(attrs, provider, reasoning_effort, runtime_id, control_port) do
    worker_ref = optional_binary(attrs, "worker_ref")

    %{
      provider: provider,
      model: optional_binary(attrs, "model"),
      reasoning_effort: reasoning_effort,
      runtime_id: runtime_id,
      workspace_id: optional_binary(attrs, "workspace_id") || "workspace-local",
      user_id: optional_binary(attrs, "user_id") || "user-local",
      participant_id: optional_binary(attrs, "participant_id") || worker_ref,
      participant_role: optional_binary(attrs, "participant_role") || "worker",
      target_id: optional_binary(attrs, "target_id") || worker_ref,
      capability_id: optional_binary(attrs, "capability_id") || "workspace.exec.session",
      workspace_root: optional_binary(attrs, "workspace_root"),
      url: optional_binary(attrs, "url") || "ws://127.0.0.1:4000/socket/websocket",
      api_base_url: optional_binary(attrs, "api_base_url"),
      control_host: optional_binary(attrs, "control_host") || "127.0.0.1",
      control_port: control_port,
      redaction_values: string_list(Map.get(attrs, "redaction_values", []))
    }
  end

  defp required_binary(attrs, key) do
    case optional_binary(attrs, key) do
      nil -> {:error, {:missing_governed_authority_field, key}}
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
          {:error, {:invalid_governed_authority_field, key}}
        end

      value when is_binary(value) ->
        case Map.fetch(values, String.downcase(String.trim(value))) do
          {:ok, atom} -> {:ok, atom}
          :error -> {:error, {:invalid_governed_authority_field, key}}
        end

      _other ->
        {:error, {:invalid_governed_authority_field, key}}
    end
  end

  defp optional_positive_integer(attrs, key) do
    case Map.get(attrs, key) do
      nil ->
        {:ok, nil}

      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer > 0 -> {:ok, integer}
          _other -> {:error, {:invalid_governed_authority_field, key}}
        end

      _other ->
        {:error, {:invalid_governed_authority_field, key}}
    end
  end

  defp string_list(values) when is_list(values) do
    Enum.filter(values, fn value -> is_binary(value) and value != "" end)
  end

  defp string_list(_other), do: []
end
