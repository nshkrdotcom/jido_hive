defmodule JidoHiveServer.Collaboration.DispatchPolicy do
  @moduledoc false

  @callback definition() :: map()
  @callback init_state(map()) :: map()
  @callback next_assignment(map(), [String.t()]) :: {:ok, map()} | {:blocked, String.t()}
  @callback next_action(map(), [String.t()]) ::
              {:ok, map()}
              | {:blocked, String.t()}
              | {:awaiting_authority, String.t()}
              | {:complete, String.t()}
  @callback status(map()) :: String.t()
end
