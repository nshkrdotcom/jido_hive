defmodule JidoHiveConsole.SwitchyardBridge do
  @moduledoc false

  @switchyard_entry "Switchyard.TUI.CLI.main(System.argv())"

  @spec run_console(keyword()) :: :ok | {:error, term()}
  def run_console(opts) do
    with {:ok, %{cmd: cmd, args: args, cd: cd}} <- command_spec(opts),
         {_, 0} <- System.cmd(cmd, args, command_opts(cd)) do
      :ok
    else
      {_, status} when is_integer(status) ->
        {:error, {:switchyard_exit, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec command_spec(keyword()) ::
          {:ok, %{cmd: String.t(), args: [String.t()], cd: String.t() | nil}} | {:error, term()}
  def command_spec(opts) do
    args = switchyard_args(opts)

    cond do
      switchyard_bin = Keyword.get(opts, :switchyard_bin) ->
        {:ok, %{cmd: switchyard_bin, args: args, cd: nil}}

      switchyard_bin = System.get_env("SWITCHYARD_BIN") ->
        {:ok, %{cmd: switchyard_bin, args: args, cd: nil}}

      switchyard_bin = System.find_executable("switchyard") ->
        {:ok, %{cmd: switchyard_bin, args: args, cd: nil}}

      binary = local_switchyard_binary() ->
        {:ok, %{cmd: binary, args: args, cd: nil}}

      app_dir = switchyard_app_dir(opts) ->
        {:ok,
         %{
           cmd: "mix",
           args: ["run", "-e", @switchyard_entry, "--" | args],
           cd: app_dir
         }}

      true ->
        {:error, :switchyard_not_found}
    end
  end

  @spec switchyard_args(keyword()) :: [String.t()]
  def switchyard_args(opts) do
    []
    |> maybe_append_option("--api-base-url", Keyword.get(opts, :api_base_url))
    |> maybe_append_option("--room-id", Keyword.get(opts, :room_id))
    |> maybe_append_option("--subject", subject(opts))
    |> maybe_append_option("--participant-id", Keyword.get(opts, :participant_id))
    |> maybe_append_option("--participant-role", Keyword.get(opts, :participant_role))
    |> maybe_append_option("--authority-level", Keyword.get(opts, :authority_level))
    |> maybe_append_flag("--debug", Keyword.get(opts, :log_level) == "debug")
  end

  defp subject(opts) do
    Keyword.get(opts, :subject) || Keyword.get(opts, :participant_id)
  end

  defp switchyard_app_dir(opts) do
    opts
    |> Keyword.get(:switchyard_app_dir, default_switchyard_app_dir())
    |> case do
      path when is_binary(path) ->
        if File.dir?(path), do: path, else: nil

      _other ->
        nil
    end
  end

  defp local_switchyard_binary do
    path = Path.join(default_switchyard_app_dir(), "switchyard")
    if File.regular?(path), do: path, else: nil
  end

  defp default_switchyard_app_dir do
    app_root = Path.expand("../..", __DIR__)
    Path.expand("../../../switchyard/apps/terminal_workbench_tui", app_root)
  end

  defp command_opts(nil),
    do: [into: IO.stream(:stdio, :line), stderr_to_stdout: true]

  defp command_opts(cd),
    do: [cd: cd, into: IO.stream(:stdio, :line), stderr_to_stdout: true]

  defp maybe_append_option(args, _flag, nil), do: args
  defp maybe_append_option(args, _flag, ""), do: args
  defp maybe_append_option(args, flag, value), do: args ++ [flag, value]

  defp maybe_append_flag(args, _flag, false), do: args
  defp maybe_append_flag(args, flag, true), do: args ++ [flag]
end
