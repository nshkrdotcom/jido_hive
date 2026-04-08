defmodule JidoHiveTermuiConsole.CLI do
  @moduledoc false

  alias JidoHiveTermuiConsole.{Auth, Config}

  @console_switches [
    api_base_url: :string,
    room_id: :string,
    participant_id: :string,
    participant_role: :string,
    authority_level: :string,
    poll_interval_ms: :integer
  ]

  @spec main([String.t()]) :: no_return()
  def main(["auth", "login", channel | _rest]) do
    :ok = Config.ensure_initialized()

    case Auth.start_device_flow(channel) do
      {:ok, %{user_code: code, verification_uri: uri}} ->
        IO.puts("Open: #{uri}")
        IO.puts("Enter code: #{code}")
        IO.puts("Credentials file: #{Config.credentials_path()}")
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
    console_argv = strip_console_prefix(argv)
    {opts, _args, _invalid} = OptionParser.parse(console_argv, strict: @console_switches)
    route = parse_args(console_argv)

    case JidoHiveTermuiConsole.run(Keyword.put(opts, :route, route)) do
      :ok ->
        System.halt(0)

      {:error, reason} ->
        IO.puts("Console failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  @spec parse_args([String.t()]) :: {:lobby, map()} | {:room, map()}
  def parse_args(argv) do
    {opts, _args, _invalid} =
      argv
      |> strip_console_prefix()
      |> OptionParser.parse(strict: @console_switches)

    case Keyword.get(opts, :room_id) do
      room_id when is_binary(room_id) and room_id != "" -> {:room, %{room_id: room_id}}
      _other -> {:lobby, %{}}
    end
  end

  defp strip_console_prefix(["console" | rest]), do: rest
  defp strip_console_prefix(argv), do: argv
end
