defmodule JidoHiveConsole do
  @moduledoc false

  alias JidoHiveConsole.SwitchyardBridge

  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts \\ []) do
    SwitchyardBridge.run_console(opts)
  end
end
