defmodule JidoHiveServer.Collaboration.Actions.SetRuntimeState do
  @moduledoc false

  use Jido.Action,
    name: "set_runtime_state",
    description: "Update high-level room runtime state without mutating room content",
    schema: [
      status: [type: :string, required: true],
      phase: [type: :string, required: true]
    ]

  alias Jido.Agent.StateOp

  @impl true
  def run(params, context) do
    state = context.state

    {:ok, %{},
     StateOp.set_state(%{
       status: params.status,
       phase: params.phase,
       current_turn: state.current_turn
     })}
  end
end
