defmodule JidoHiveClient.ExecutionContract do
  @moduledoc false

  alias ASM.Execution.Environment
  alias CliSubprocessCore.ExecutionSurface

  @provider_option_keys [:model, :reasoning_effort, :cli_path]

  @spec apply_session_defaults(map(), keyword()) :: keyword()
  def apply_session_defaults(job, opts) when is_map(job) and is_list(opts) do
    opts
    |> put_new_opt(:provider, provider_from_job(job))
    |> put_new_opt(:model, provider_option(job, :model))
    |> put_new_opt(
      :reasoning_effort,
      normalize_reasoning_effort(provider_option(job, :reasoning_effort))
    )
    |> put_new_opt(:cli_path, provider_option(job, :cli_path))
    |> put_new_opt(:execution_surface, execution_surface(job))
    |> put_new_opt(:execution_environment, execution_environment(job))
  end

  @spec workspace_root(map(), keyword()) :: String.t()
  def workspace_root(job, opts \\ []) when is_map(job) and is_list(opts) do
    Keyword.get(opts, :cwd) ||
      execution_environment_workspace_root(execution_environment(job)) ||
      session_value(job, "workspace_root") ||
      Map.get(job, "workspace_root") ||
      File.cwd!()
  end

  @spec allowed_tools(map(), keyword()) :: [String.t()]
  def allowed_tools(job, opts \\ []) when is_map(job) and is_list(opts) do
    case Keyword.get(
           opts,
           :allowed_tools,
           execution_environment_allowed_tools(execution_environment(job))
         ) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  @spec start_session_opts(map(), keyword(), atom(), String.t()) :: keyword()
  def start_session_opts(job, opts, provider, session_id)
      when is_map(job) and is_list(opts) and is_atom(provider) and is_binary(session_id) do
    opts
    |> Keyword.drop([:run_id, :allowed_tools, :timeout_ms, :model])
    |> Keyword.put_new(:provider, provider)
    |> Keyword.put_new(:session_id, session_id)
    |> Keyword.put_new(:cwd, workspace_root(job, opts))
    |> put_new_opt(:execution_surface, execution_surface(job))
    |> put_new_opt(:execution_environment, execution_environment(job))
  end

  @spec target_registration_payload(keyword(), String.t()) :: map()
  def target_registration_payload(executor_opts, workspace_root)
      when is_list(executor_opts) and is_binary(workspace_root) do
    %{
      "provider" => provider_string(Keyword.get(executor_opts, :provider, :codex)),
      "workspace_root" => workspace_root,
      "execution_surface" =>
        execution_surface_payload(Keyword.get(executor_opts, :execution_surface)),
      "execution_environment" =>
        execution_environment_payload(
          Keyword.get(executor_opts, :execution_environment),
          workspace_root
        ),
      "provider_options" => provider_options_payload(executor_opts)
    }
    |> compact_map()
  end

  @spec execution_surface(map()) :: map() | nil
  def execution_surface(job) when is_map(job) do
    session_value(job, "execution_surface")
  end

  @spec execution_environment(map()) :: map() | nil
  def execution_environment(job) when is_map(job) do
    case session_value(job, "execution_environment") do
      %{} = environment ->
        environment

      _other ->
        case session_value(job, "workspace_root") || Map.get(job, "workspace_root") do
          root when is_binary(root) and root != "" -> %{"workspace_root" => root}
          _ -> nil
        end
    end
  end

  @spec provider_option(map(), atom()) :: term()
  def provider_option(job, key)
      when is_map(job) and is_atom(key) and key in @provider_option_keys do
    job
    |> session_value("provider_options")
    |> value_from_map(key)
  end

  defp provider_from_job(job) when is_map(job) do
    case session_value(job, "provider") || Map.get(job, "provider") do
      value when is_binary(value) and value != "" -> String.to_atom(value)
      value when is_atom(value) -> value
      _other -> :codex
    end
  end

  defp execution_environment_workspace_root(%{} = environment) do
    value_from_map(environment, :workspace_root)
  end

  defp execution_environment_workspace_root(_other), do: nil

  defp execution_environment_allowed_tools(%{} = environment) do
    case value_from_map(environment, :allowed_tools) do
      values when is_list(values) -> Enum.filter(values, &is_binary/1)
      _other -> []
    end
  end

  defp execution_environment_allowed_tools(_other), do: []

  defp provider_string(value) when is_atom(value), do: Atom.to_string(value)
  defp provider_string(value) when is_binary(value), do: value
  defp provider_string(_other), do: "codex"

  defp normalize_reasoning_effort(nil), do: nil
  defp normalize_reasoning_effort(value) when is_atom(value), do: value

  defp normalize_reasoning_effort(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> String.to_atom(String.downcase(normalized))
    end
  end

  defp normalize_reasoning_effort(_other), do: nil

  defp execution_surface_payload(nil), do: nil

  defp execution_surface_payload(surface) do
    case ExecutionSurface.new(surface) do
      {:ok, %ExecutionSurface{} = normalized} ->
        normalized
        |> Map.from_struct()
        |> Map.update!(:transport_options, &keyword_to_string_map/1)
        |> stringify_keys()

      {:error, _reason} ->
        nil
    end
  end

  defp execution_environment_payload(nil, workspace_root) do
    %{"workspace_root" => workspace_root}
  end

  defp execution_environment_payload(environment, workspace_root) do
    attrs =
      case Environment.new(environment) do
        {:ok, %Environment{} = normalized} ->
          normalized
          |> Environment.to_attrs()
          |> Keyword.put_new(:workspace_root, workspace_root)

        {:error, _reason} ->
          [workspace_root: workspace_root]
      end

    attrs
    |> keyword_to_string_map()
    |> compact_map()
  end

  defp provider_options_payload(opts) when is_list(opts) do
    @provider_option_keys
    |> Enum.reduce(%{}, fn key, acc ->
      case Keyword.get(opts, key) do
        nil -> acc
        value -> Map.put(acc, Atom.to_string(key), payload_value(key, value))
      end
    end)
    |> case do
      map when map_size(map) == 0 -> nil
      map -> map
    end
  end

  defp payload_value(:reasoning_effort, value) when is_atom(value), do: Atom.to_string(value)
  defp payload_value(_key, value), do: value

  defp session_value(job, key) when is_map(job) do
    case Map.get(job, "session") || Map.get(job, :session) do
      %{} = session -> value_from_map(session, key)
      _other -> nil
    end
  end

  defp value_from_map(nil, _key), do: nil

  defp value_from_map(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp value_from_map(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp put_new_opt(opts, _key, nil), do: opts

  defp put_new_opt(opts, key, value) when is_list(opts) do
    if Keyword.has_key?(opts, key), do: opts, else: Keyword.put(opts, key, value)
  end

  defp keyword_to_string_map(keyword) when is_list(keyword) do
    keyword
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), normalize_payload_value(value)} end)
    |> Map.new()
  end

  defp normalize_payload_value(value) when is_list(value) do
    if Keyword.keyword?(value) do
      keyword_to_string_map(value)
    else
      Enum.map(value, &normalize_payload_value/1)
    end
  end

  defp normalize_payload_value(value) when is_map(value), do: stringify_keys(value)
  defp normalize_payload_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_payload_value(value), do: value

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), normalize_payload_value(value)} end)
    |> Map.new()
  end

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn
      {_key, nil} -> true
      {_key, %{} = value} -> map_size(value) == 0
      _ -> false
    end)
    |> Map.new()
  end
end
