defmodule JidoHiveClient.CLI do
  @moduledoc false

  require Logger

  alias JidoHiveClient.{DebugTrace, EscriptBootstrap, HeadlessCLI}

  @structured_log_modules [
    __MODULE__,
    JidoHiveClient.Boundary.RoomApi.Http,
    JidoHiveClient.Embedded,
    JidoHiveClient.HeadlessCLI,
    JidoHiveClient.Operator,
    JidoHiveClient.Operator.HTTP
  ]

  @spec main([String.t()]) :: no_return()
  def main(args) do
    args
    |> run_headless()
    |> System.halt()
  end

  @doc false
  @spec run_headless([String.t()]) :: 0 | 1
  defp run_headless(args) do
    {log_level, command_args} = extract_log_level(args)

    configure_logger(log_level)
    :ok = EscriptBootstrap.start_cli_dependencies()
    started_at = System.monotonic_time(:millisecond)

    DebugTrace.emit(:info, "headless.command.started", %{
      argv: command_args,
      command_family: List.first(command_args)
    })

    case HeadlessCLI.dispatch(command_args) do
      {:ok, output} ->
        DebugTrace.emit(:info, "headless.command.completed", %{
          argv: command_args,
          elapsed_ms: System.monotonic_time(:millisecond) - started_at,
          status: "ok"
        })

        IO.puts(Jason.encode!(output, pretty: true))
        0

      {:error, reason} ->
        DebugTrace.emit(:error, "headless.command.failed", %{
          argv: command_args,
          elapsed_ms: System.monotonic_time(:millisecond) - started_at,
          reason: inspect(reason)
        })

        IO.puts("Command failed: #{inspect(reason)}")
        1
    end
  end

  defp extract_log_level(["--log-level", level | rest]), do: {parse_log_level(level), rest}

  defp extract_log_level([<<"--log-level=", level::binary>> | rest]),
    do: {parse_log_level(level), rest}

  defp extract_log_level(args), do: {configured_log_level(), args}

  defp configured_log_level do
    :jido_hive_client
    |> Application.get_env(:log_level, :warning)
    |> parse_log_level()
  end

  defp configure_logger(level) do
    Logger.configure(level: primary_logger_level(level))
    Application.put_env(:jido_hive_client, :debug_trace_level, debug_trace_level(level))
    clear_structured_module_levels()
    apply_structured_module_levels(level)
  end

  defp parse_log_level(level) when is_atom(level), do: parse_log_level(Atom.to_string(level))
  defp parse_log_level("debug"), do: :debug
  defp parse_log_level("info"), do: :info
  defp parse_log_level("warning"), do: :warning
  defp parse_log_level("error"), do: :error
  defp parse_log_level(_other), do: :warning

  defp primary_logger_level(:debug), do: :warning
  defp primary_logger_level(:info), do: :warning
  defp primary_logger_level(level), do: level

  defp debug_trace_level(level) when level in [:debug, :info], do: level
  defp debug_trace_level(_level), do: nil

  defp clear_structured_module_levels do
    Enum.each(@structured_log_modules, &Logger.delete_module_level/1)
  end

  defp apply_structured_module_levels(level) when level in [:debug, :info] do
    Enum.each(@structured_log_modules, &Logger.put_module_level(&1, level))
  end

  defp apply_structured_module_levels(_level), do: :ok
end
