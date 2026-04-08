defmodule JidoHiveTermuiConsole.CLI do
  @moduledoc false

  alias JidoHiveTermuiConsole.{Auth, Config}

  @local_api_base_url "http://127.0.0.1:4000/api"
  @prod_api_base_url "https://jido-hive-server-test.app.nsai.online/api"

  @console_switches [
    local: :boolean,
    prod: :boolean,
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
    opts = parse_console_opts(argv)
    route = parse_args(argv)

    case JidoHiveTermuiConsole.run(Keyword.put(opts, :route, route)) do
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
    |> resolve_mode_api_base_url()
    |> Keyword.drop([:local, :prod])
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
end
