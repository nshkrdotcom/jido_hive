defmodule JidoHiveTermuiConsole.LoggerSetup do
  @moduledoc false

  require Logger

  alias JidoHiveTermuiConsole.Config

  @handler_name :jido_hive_termui_console_file
  @default_handler :default
  @default_handler_filter_key {__MODULE__, :default_handler_filter_default}
  @default_level "info"
  @env_level "JIDO_HIVE_TERMUI_LOG_LEVEL"
  @env_path "JIDO_HIVE_TERMUI_LOG_PATH"

  @spec configure(keyword()) :: :ok
  def configure(opts \\ []) do
    {:ok, _apps} = Application.ensure_all_started(:logger)
    :ok = Config.ensure_initialized()

    level = resolve_level(opts)
    path = resolve_path(opts)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "", [:append])
    :ok = Logger.configure(level: level)
    :ok = attach_file_handler(path, level)
    :ok = suppress_default_handler()
    Logger.log(level, "termui console logger configured path=#{path} level=#{level}")
    Logger.flush()
    :ok
  end

  @spec restore() :: :ok
  def restore do
    case :persistent_term.get(@default_handler_filter_key, :unset) do
      :unset ->
        :ok

      previous_filter_default ->
        :persistent_term.erase(@default_handler_filter_key)
        :logger.set_handler_config(@default_handler, :filter_default, previous_filter_default)
    end
  end

  @spec default_log_path() :: String.t()
  def default_log_path do
    Path.join(Config.config_dir(), "termui_console.log")
  end

  defp resolve_level(opts) do
    opts
    |> Keyword.get(:log_level, System.get_env(@env_level, @default_level))
    |> normalize_level()
  end

  defp resolve_path(opts) do
    Keyword.get(opts, :log_file, System.get_env(@env_path, default_log_path()))
  end

  defp normalize_level("debug"), do: :debug
  defp normalize_level("info"), do: :info
  defp normalize_level("warning"), do: :warning
  defp normalize_level("error"), do: :error
  defp normalize_level(level) when is_atom(level), do: level
  defp normalize_level(_other), do: :info

  defp attach_file_handler(path, level) do
    _ =
      case :logger.get_handler_config(@handler_name) do
        {:ok, _config} -> :logger.remove_handler(@handler_name)
        _other -> :ok
      end

    config = %{
      level: level,
      config: %{
        file: String.to_charlist(path),
        filesync_repeat_interval: 5_000,
        file_check: 5_000
      },
      formatter: Logger.Formatter.new(colors: [enabled: false])
    }

    case :logger.add_handler(@handler_name, :logger_std_h, config) do
      :ok ->
        :ok

      {:error, {:already_exist, @handler_name}} ->
        :ok

      {:error, reason} ->
        raise "failed to attach logger handler: #{inspect(reason)}"
    end
  end

  defp suppress_default_handler do
    case :logger.get_handler_config(@default_handler) do
      {:ok, %{filter_default: filter_default}} ->
        if :persistent_term.get(@default_handler_filter_key, :unset) == :unset do
          :persistent_term.put(@default_handler_filter_key, filter_default)
        end

        :logger.set_handler_config(@default_handler, :filter_default, :stop)

      _other ->
        :ok
    end
  end
end
