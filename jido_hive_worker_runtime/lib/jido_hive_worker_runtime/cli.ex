defmodule JidoHiveWorkerRuntime.CLI do
  @moduledoc false

  require Logger

  alias JidoHiveWorkerRuntime.{EscriptBootstrap, RelayWorker, Status}

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
    with {:ok, parsed} <- parse_args(args) do
      {:ok, normalize_cli_opts(parsed)}
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
      --relay-topic TOPIC
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
          relay_topic: :string,
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
          control_host: :string
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
      relay_topic: Keyword.get(opts, :relay_topic, "relay:#{workspace_id}"),
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
      :runtime_id
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

  defp parse_provider(provider) when is_binary(provider), do: String.to_atom(provider)
  defp parse_provider(provider) when is_atom(provider), do: provider

  defp parse_reasoning_effort(nil), do: nil
  defp parse_reasoning_effort(value) when is_atom(value), do: value

  defp parse_reasoning_effort(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      effort -> String.to_atom(effort)
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
