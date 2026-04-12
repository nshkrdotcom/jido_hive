defmodule JidoHiveWorkerRuntime.AssignmentBuilder do
  @moduledoc false

  alias Jido.Harness.RunRequest

  @callback build(map(), keyword()) :: RunRequest.t()
  @callback repair(String.t(), map(), keyword()) :: RunRequest.t()
end
