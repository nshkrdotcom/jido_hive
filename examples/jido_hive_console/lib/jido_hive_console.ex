defmodule JidoHiveConsole do
  @moduledoc false

  alias JidoHiveClient.EscriptBootstrap

  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts \\ []) do
    bootstrap_module = Keyword.get(opts, :bootstrap_module, EscriptBootstrap)
    :ok = bootstrap_module.start_cli_dependencies()
    Keyword.get(opts, :tui_module, JidoHive.Switchyard.TUI).run(opts)
  end
end
