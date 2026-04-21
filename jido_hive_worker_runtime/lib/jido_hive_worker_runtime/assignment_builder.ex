defmodule JidoHiveWorkerRuntime.AssignmentBuilder do
  @moduledoc false

  alias Jido.RuntimeControl.RunRequest

  @callback build(map(), keyword()) :: RunRequest.t()
  @callback repair(String.t(), map(), keyword()) :: RunRequest.t()
end
