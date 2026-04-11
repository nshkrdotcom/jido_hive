defmodule JidoHiveConsole do
  @moduledoc false

  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts \\ []) do
    Keyword.get(opts, :tui_module, JidoHive.Switchyard.TUI).run(opts)
  end
end
