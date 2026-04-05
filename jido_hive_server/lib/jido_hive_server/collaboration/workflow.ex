defmodule JidoHiveServer.Collaboration.Workflow do
  @moduledoc false

  @callback id() :: String.t()
  @callback load_defaults(map()) :: map()
  @callback stages(map()) :: [map()]
  @callback next_assignment(map(), [String.t()]) :: {:ok, map()} | {:error, atom()} | :halt
  @callback status(map()) :: String.t()
end
