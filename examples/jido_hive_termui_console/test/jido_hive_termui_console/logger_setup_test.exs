defmodule JidoHiveTermuiConsole.LoggerSetupTest do
  use ExUnit.Case, async: false

  require Logger

  alias JidoHiveTermuiConsole.LoggerSetup

  @handler_name :jido_hive_termui_console_file

  setup do
    path =
      Path.join(System.tmp_dir!(), "jido-hive-termui-#{System.unique_integer([:positive])}.log")

    previous_level = Logger.level()

    on_exit(fn ->
      Logger.configure(level: previous_level)

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

    assert File.read!(path) =~ "termui console logger configured"

    Logger.debug("termui logger setup test")
    Logger.flush()
    Process.sleep(50)

    assert File.read!(path) =~ "termui logger setup test"
    refute File.read!(path) =~ "\e["
  end
end
