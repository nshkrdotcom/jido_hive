defmodule JidoHiveConsole.CLI do
  @moduledoc false

  require Logger

  alias JidoHiveClient.Operator
  alias JidoHiveConsole.{EscriptBootstrap, LoggerSetup, WorkflowScript}

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

  def main(["workflow", "room-smoke" | rest]) do
    opts = parse_console_opts(rest)

    result =
      with :ok <- LoggerSetup.configure(opts),
           :ok <- EscriptBootstrap.start_console_dependencies(),
           {:ok, output} <-
             WorkflowScript.run(rest, api_base_url: Keyword.get(opts, :api_base_url)) do
        IO.puts(Jason.encode!(output, pretty: true))
        :ok
      else
        {:error, reason} -> {:error, reason}
      end

    :ok = LoggerSetup.restore()

    case result do
      :ok ->
        System.halt(0)

      {:error, reason} ->
        IO.puts("Workflow failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  @spec main([String.t()]) :: no_return()
  def main(["auth", "login", channel | _rest]) do
    :ok = Operator.ensure_initialized()

    case Operator.start_device_flow(channel) do
      {:ok, %{user_code: code, verification_uri: uri}} ->
        IO.puts("Open: #{uri}")
        IO.puts("Enter code: #{code}")
        IO.puts("Credentials file: #{Operator.credentials_path()}")
        IO.puts("This is the v1 device-flow scaffold. Complete authorization externally.")
        System.halt(0)

      {:error, reason} ->
        IO.puts("Auth failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  def main(["room", "create" | _rest]) do
    IO.puts(
      "Non-interactive room creation is not implemented in the CLI stub. Use `hive console`."
    )

    System.halt(1)
  end

  def main(argv) do
    opts = parse_console_opts(argv)
    route = parse_args(argv)

    result =
      with :ok <- LoggerSetup.configure(opts),
           :ok <- log_console_start(opts, route),
           :ok <- EscriptBootstrap.start_console_dependencies(),
           :ok <- JidoHiveConsole.run(Keyword.put(opts, :route, route)) do
        :ok
      else
        {:error, reason} -> {:error, reason}
      end

    :ok = LoggerSetup.restore()

    case result do
      :ok ->
        System.halt(0)

      {:error, reason} ->
        IO.puts("Console failed: #{inspect(reason)}")
        System.halt(1)
    end
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

  defp log_console_start(opts, route) do
    Logger.info(
      "starting console route=#{inspect(route)} api_base_url=#{Keyword.get(opts, :api_base_url)} participant_id=#{Keyword.get(opts, :participant_id, "human-local")} log_level=#{Keyword.get(opts, :log_level, "info")}"
    )

    Logger.flush()
    :ok
  end
end
