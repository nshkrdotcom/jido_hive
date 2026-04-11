defmodule JidoHiveConsole.CLI do
  @moduledoc false

  alias JidoHiveConsole.WorkflowScript

  @local_api_base_url "http://127.0.0.1:4000/api"
  @prod_api_base_url "https://jido-hive-server-test.app.nsai.online/api"

  @console_switches [
    debug: :boolean,
    local: :boolean,
    prod: :boolean,
    api_base_url: :string,
    room_id: :string,
    participant_id: :string,
    participant_role: :string,
    authority_level: :string,
    poll_interval_ms: :integer,
    tenant_id: :string,
    actor_id: :string,
    log_level: :string,
    log_file: :string
  ]

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    System.halt(run_status(argv))
  end

  @doc false
  @spec run_status([String.t()]) :: 0 | 1
  def run_status(["help"]), do: print_help(help_text(:main))
  def run_status(["--help"]), do: print_help(help_text(:main))
  def run_status(["console", "help"]), do: print_help(help_text(:console))
  def run_status(["console", "--help"]), do: print_help(help_text(:console))

  def run_status(["workflow", "room-smoke", "help"]),
    do: print_help(help_text(:workflow_room_smoke))

  def run_status(["workflow", "room-smoke", "--help"]),
    do: print_help(help_text(:workflow_room_smoke))

  def run_status(["workflow", "room-smoke" | rest]) do
    opts = parse_console_opts(rest)

    case WorkflowScript.run(rest, api_base_url: Keyword.get(opts, :api_base_url)) do
      {:ok, output} ->
        IO.puts(Jason.encode!(output, pretty: true))
        0

      {:error, reason} ->
        IO.puts("Workflow failed: #{inspect(reason)}")
        1
    end
  end

  def run_status(argv) do
    opts = parse_console_opts(argv)

    case JidoHiveConsole.run(opts) do
      :ok ->
        0

      {:error, reason} ->
        IO.puts("Console failed: #{inspect(reason)}")
        1
    end
  end

  @doc false
  @spec help_text(:main | :console | :workflow_room_smoke) :: String.t()
  def help_text(:main) do
    """
    Switchyard-backed Jido Hive operator console.

    Commands:
      hive console [--local | --prod | --api-base-url URL] [--participant-id ID] [--room-id ID] [--debug]
      hive workflow room-smoke [--local | --prod | --api-base-url URL] [--brief TEXT] [--text TEXT]...

    Help:
      hive help
      hive console --help
      hive workflow room-smoke --help
    """
    |> String.trim()
  end

  def help_text(:console) do
    """
    Usage:
      hive console [--local | --prod | --api-base-url URL] [options]

    Important options:
      --participant-id ID
      --participant-role ROLE
      --authority-level LEVEL
      --room-id ID
      --tenant-id ID
      --actor-id ID
      --debug
      --log-level LEVEL
    """
    |> String.trim()
  end

  def help_text(:workflow_room_smoke) do
    """
    Usage:
      hive workflow room-smoke [--local | --prod | --api-base-url URL] [options]

    Important options:
      --room-id ID
      --brief TEXT
      --participant-id ID
      --participant-role ROLE
      --authority-level LEVEL
      --text TEXT
      --run
      --max-assignments N
      --assignment-timeout-ms N
    """
    |> String.trim()
  end

  @spec parse_console_opts([String.t()]) :: keyword()
  def parse_console_opts(argv) do
    {opts, _args, _invalid} =
      argv
      |> strip_console_prefix()
      |> OptionParser.parse(strict: @console_switches)

    opts
    |> resolve_log_level()
    |> resolve_mode_api_base_url()
    |> Keyword.drop([:debug, :local, :prod])
  end

  @spec parse_args([String.t()]) :: {:lobby, map()} | {:room, map()}
  def parse_args(argv) do
    opts = parse_console_opts(argv)

    case Keyword.get(opts, :room_id) do
      room_id when is_binary(room_id) and room_id != "" -> {:room, %{room_id: room_id}}
      _other -> {:lobby, %{}}
    end
  end

  defp strip_console_prefix(["console" | rest]), do: rest
  defp strip_console_prefix(argv), do: argv

  defp resolve_log_level(opts) do
    cond do
      Keyword.has_key?(opts, :log_level) ->
        opts

      Keyword.get(opts, :debug, false) ->
        Keyword.put(opts, :log_level, "debug")

      true ->
        opts
    end
  end

  defp resolve_mode_api_base_url(opts) do
    cond do
      Keyword.has_key?(opts, :api_base_url) ->
        opts

      Keyword.get(opts, :prod, false) ->
        Keyword.put(opts, :api_base_url, @prod_api_base_url)

      Keyword.get(opts, :local, false) ->
        Keyword.put(opts, :api_base_url, @local_api_base_url)

      true ->
        opts
    end
  end

  @spec print_help(String.t()) :: 0
  defp print_help(output) do
    IO.puts(output)
    0
  end
end
