defmodule JidoHiveWorkerRuntime.CLI do
  @moduledoc false

  require Logger

  alias JidoHiveWorkerRuntime.{EscriptBootstrap, GovernedAuthority, RelayWorker, Status}

  @structured_log_modules [
    __MODULE__,
    JidoHiveWorkerRuntime.Status
  ]

  @spec main([String.t()]) :: no_return()
  def main(args) do
    case run(args) do
      {:ok, opts} ->
        configure_logger()
        :ok = EscriptBootstrap.start_cli_dependencies()
        configure_application(opts)

        {:ok, _apps} = Application.ensure_all_started(:jido_hive_worker_runtime)
        Status.client_start(opts)

        {:ok, _pid} = RelayWorker.start_link(opts)
        Process.sleep(:infinity)

      {:help, output} ->
        IO.puts(output)
        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, "Worker runtime failed: #{format_error(reason)}")
        System.halt(1)
    end
  end

  @doc false
  @spec run([String.t()]) :: {:ok, keyword()} | {:help, String.t()} | {:error, term()}
  def run(["help"]), do: {:help, help_text()}
  def run(["-h"]), do: {:help, help_text()}
  def run(["--help"]), do: {:help, help_text()}

  def run(args) when is_list(args) do
    case parse_args(args) do
      {:ok, parsed} -> normalize_cli_opts(parsed)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec help_text() :: String.t()
  def help_text do
    """
    Usage:
      jido_hive_worker [options]

    Important options:
      --url URL
      --api-base-url URL
      --room-id ID
      --workspace-id ID
      --participant-id ID
      --participant-role ROLE
      --target-id ID
      --user-id ID
      --capability-id ID
      --workspace-root PATH
      --provider PROVIDER
      --model MODEL
      --reasoning-effort LEVEL
      --timeout-ms N
      --cli-path PATH
      --control-port N
      --control-host HOST
    """
    |> String.trim()
  end

  defp parse_args(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          url: :string,
          api_base_url: :string,
          room_id: :keep,
          workspace_id: :string,
          user_id: :string,
          participant_id: :string,
          participant_role: :string,
          target_id: :string,
          capability_id: :string,
          workspace_root: :string,
          provider: :string,
          model: :string,
          reasoning_effort: :string,
          timeout_ms: :integer,
          cli_path: :string,
          control_port: :integer,
          control_host: :string,
          governed_authority_ref: :string,
          governed_worker_ref: :string,
          governed_credential_ref: :string,
          governed_provider: :string,
          governed_model: :string,
          governed_reasoning_effort: :string,
          governed_runtime_id: :string,
          governed_workspace_id: :string,
          governed_user_id: :string,
          governed_participant_id: :string,
          governed_participant_role: :string,
          governed_target_id: :string,
          governed_capability_id: :string,
          governed_workspace_root: :string,
          governed_url: :string,
          governed_api_base_url: :string,
          governed_control_port: :integer,
          governed_control_host: :string
        ]
      )

    cond do
      invalid != [] ->
        {:error, {:invalid_options, invalid}}

      rest != [] ->
        {:error, {:unexpected_arguments, rest}}

      true ->
        {:ok, opts}
    end
  end

  defp normalize_cli_opts(opts) do
    case Keyword.get(opts, :governed_authority_ref) do
      nil -> {:ok, standalone_cli_opts(opts)}
      _authority_ref -> governed_cli_opts(opts)
    end
  end

  defp standalone_cli_opts(opts) do
    workspace_id = Keyword.get(opts, :workspace_id, "workspace-local")

    control_port =
      Keyword.get(opts, :control_port) || env_integer("JIDO_HIVE_CLIENT_CONTROL_PORT")

    control_host =
      Keyword.get(
        opts,
        :control_host,
        System.get_env("JIDO_HIVE_CLIENT_CONTROL_HOST", "127.0.0.1")
      )

    [
      url: Keyword.get(opts, :url, "ws://127.0.0.1:4000/socket/websocket"),
      api_base_url: Keyword.get(opts, :api_base_url),
      room_ids: Keyword.get_values(opts, :room_id),
      workspace_id: workspace_id,
      user_id: Keyword.get(opts, :user_id, "user-local"),
      participant_id: Keyword.get(opts, :participant_id, "participant-local"),
      participant_role: Keyword.get(opts, :participant_role, "architect"),
      target_id: Keyword.get(opts, :target_id, "target-local"),
      capability_id: Keyword.get(opts, :capability_id, "workspace.exec.session"),
      workspace_root: Keyword.get(opts, :workspace_root, File.cwd!()),
      runtime_id: :asm,
      control_port: control_port,
      control_host: control_host,
      runtime: JidoHiveWorkerRuntime.Runtime,
      executor:
        {JidoHiveWorkerRuntime.Executor.Session,
         [
           provider: parse_provider(Keyword.get(opts, :provider, "codex")),
           model: Keyword.get(opts, :model),
           reasoning_effort: parse_reasoning_effort(Keyword.get(opts, :reasoning_effort, "low")),
           timeout_ms: Keyword.get(opts, :timeout_ms),
           cli_path: Keyword.get(opts, :cli_path)
         ]}
    ]
  end

  @governed_direct_fields [
    :url,
    :api_base_url,
    :workspace_id,
    :user_id,
    :participant_id,
    :participant_role,
    :target_id,
    :capability_id,
    :workspace_root,
    :provider,
    :model,
    :reasoning_effort,
    :timeout_ms,
    :cli_path,
    :control_port,
    :control_host
  ]

  defp governed_cli_opts(opts) do
    with :ok <- reject_governed_direct_fields(opts),
         {:ok, authority} <- GovernedAuthority.new(governed_authority_attrs(opts)) do
      {:ok, GovernedAuthority.worker_opts(authority)}
    end
  end

  defp reject_governed_direct_fields(opts) do
    case Enum.find(@governed_direct_fields, &Keyword.has_key?(opts, &1)) do
      nil -> :ok
      field -> {:error, {:governed_direct_worker_field, field}}
    end
  end

  defp governed_authority_attrs(opts) do
    %{
      authority_ref: Keyword.get(opts, :governed_authority_ref),
      worker_ref: Keyword.get(opts, :governed_worker_ref),
      credential_ref: Keyword.get(opts, :governed_credential_ref),
      provider: Keyword.get(opts, :governed_provider),
      model: Keyword.get(opts, :governed_model),
      reasoning_effort: Keyword.get(opts, :governed_reasoning_effort),
      runtime_id: Keyword.get(opts, :governed_runtime_id),
      workspace_id: Keyword.get(opts, :governed_workspace_id),
      user_id: Keyword.get(opts, :governed_user_id),
      participant_id: Keyword.get(opts, :governed_participant_id),
      participant_role: Keyword.get(opts, :governed_participant_role),
      target_id: Keyword.get(opts, :governed_target_id),
      capability_id: Keyword.get(opts, :governed_capability_id),
      workspace_root: Keyword.get(opts, :governed_workspace_root),
      url: Keyword.get(opts, :governed_url),
      api_base_url: Keyword.get(opts, :governed_api_base_url),
      control_port: Keyword.get(opts, :governed_control_port),
      control_host: Keyword.get(opts, :governed_control_host)
    }
  end

  defp configure_application(opts) when is_list(opts) do
    Application.put_env(:jido_hive_worker_runtime, :runtime, runtime_opts(opts))
    Application.put_env(:jido_hive_worker_runtime, :control_api, control_opts(opts))
  end

  defp runtime_opts(opts) when is_list(opts) do
    opts
    |> Keyword.take([
      :workspace_id,
      :user_id,
      :participant_id,
      :participant_role,
      :target_id,
      :capability_id,
      :workspace_root,
      :executor,
      :runtime_id,
      :governed_authority_ref,
      :credential_ref,
      :redaction_values
    ])
    |> Keyword.put(:name, JidoHiveWorkerRuntime.Runtime)
  end

  defp control_opts(opts) when is_list(opts) do
    case Keyword.get(opts, :control_port) do
      port when is_integer(port) and port > 0 ->
        [
          enabled: true,
          runtime: Keyword.get(opts, :runtime, JidoHiveWorkerRuntime.Runtime),
          port: port,
          host: Keyword.get(opts, :control_host, "127.0.0.1")
        ]

      _other ->
        [enabled: false]
    end
  end

  defp configure_logger do
    level = parse_log_level(System.get_env("JIDO_HIVE_CLIENT_LOG_LEVEL", "warning"))

    Logger.configure(level: primary_logger_level(level))
    clear_structured_module_levels()
    apply_structured_module_levels(level)
  end

  defp parse_log_level("debug"), do: :debug
  defp parse_log_level("info"), do: :info
  defp parse_log_level("warning"), do: :warning
  defp parse_log_level("error"), do: :error
  defp parse_log_level(_other), do: :warning

  defp primary_logger_level(:debug), do: :warning
  defp primary_logger_level(:info), do: :warning
  defp primary_logger_level(level), do: level

  defp clear_structured_module_levels do
    Enum.each(@structured_log_modules, &Logger.delete_module_level/1)
  end

  defp apply_structured_module_levels(level) when level in [:debug, :info] do
    Enum.each(@structured_log_modules, &Logger.put_module_level(&1, level))
  end

  defp apply_structured_module_levels(_level), do: :ok

  defp parse_provider(provider) when is_binary(provider) do
    case String.downcase(String.trim(provider)) do
      "amp" -> :amp
      "claude" -> :claude
      "codex" -> :codex
      "gemini" -> :gemini
      "mock" -> :mock
      "scripted" -> :scripted
      _other -> :codex
    end
  end

  defp parse_provider(provider) when is_atom(provider), do: provider

  defp parse_reasoning_effort(nil), do: nil
  defp parse_reasoning_effort(value) when is_atom(value), do: value

  defp parse_reasoning_effort(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      "low" -> :low
      "medium" -> :medium
      "high" -> :high
      "xhigh" -> :xhigh
      _other -> nil
    end
  end

  defp env_integer(name) when is_binary(name) do
    case System.get_env(name) do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _other -> nil
        end
    end
  end

  defp format_error({:invalid_options, invalid}), do: "invalid CLI arguments: #{inspect(invalid)}"

  defp format_error({:unexpected_arguments, rest}),
    do: "unexpected CLI arguments: #{inspect(rest)}"
end
