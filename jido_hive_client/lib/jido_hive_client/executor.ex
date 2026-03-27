defmodule JidoHiveClient.Executor do
  @moduledoc false

  @callback run(map(), keyword()) :: {:ok, map()} | {:error, term()}
end
