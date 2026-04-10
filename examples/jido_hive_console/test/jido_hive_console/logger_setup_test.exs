defmodule JidoHiveConsole.LoggerSetupTest do
  use ExUnit.Case, async: false

  require Logger

  alias JidoHiveConsole.LoggerSetup

  @handler_name :jido_hive_console_file

  setup do
    path =
      Path.join(System.tmp_dir!(), "jido-hive-console-#{System.unique_integer([:positive])}.log")

    previous_level = Logger.level()
    {:ok, previous_default_handler} = :logger.get_handler_config(:default)

    on_exit(fn ->
      LoggerSetup.restore()
      Logger.configure(level: previous_level)

      :logger.set_handler_config(
        :default,
        :filter_default,
        previous_default_handler.filter_default
      )

      case :logger.get_handler_config(@handler_name) do
        {:ok, _config} -> :logger.remove_handler(@handler_name)
        _other -> :ok
      end

      File.rm(path)
    end)

    {:ok, path: path}
  end

  test "configure writes logs to the configured file", %{path: path} do
    assert :ok = LoggerSetup.configure(log_level: "debug", log_file: path)
    Logger.flush()

    assert File.read!(path) =~ "console logger configured"
    assert {:ok, %{filter_default: :stop}} = :logger.get_handler_config(:default)

    Logger.debug("console logger setup test")
    Logger.flush()
    Process.sleep(50)

    assert File.read!(path) =~ "console logger setup test"
    refute File.read!(path) =~ "\e["

    assert :ok = LoggerSetup.restore()
    assert {:ok, %{filter_default: :log}} = :logger.get_handler_config(:default)
  end
end
