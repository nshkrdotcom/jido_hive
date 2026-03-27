defmodule JidoHiveServer.Collaboration.Actions.OpenTurn do
  @moduledoc false

  use Jido.Action,
    name: "open_turn",
    description: "Open a room turn for one participant",
    schema: [
      job_id: [type: :string, required: true],
      participant_id: [type: :string, required: true],
      round: [type: :integer, required: true],
      prompt_packet: [type: :map, default: %{}]
    ]

  alias Jido.Agent.StateOp

  @impl true
  def run(params, context) do
    state = context.state

    turn = %{
      job_id: params.job_id,
      participant_id: params.participant_id,
      round: params.round,
      prompt_packet: params.prompt_packet,
      status: :running
    }

    {:ok, %{},
     StateOp.set_state(%{
       current_turn: turn,
       turns: state.turns ++ [turn],
       round: params.round,
       status: "running"
     })}
  end
end
