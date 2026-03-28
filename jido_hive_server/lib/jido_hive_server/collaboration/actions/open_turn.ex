defmodule JidoHiveServer.Collaboration.Actions.OpenTurn do
  @moduledoc false

  use Jido.Action,
    name: "open_turn",
    description: "Open a room turn for one participant",
    schema: [
      job_id: [type: :string, required: true],
      plan_slot_index: [type: :integer, required: true],
      participant_id: [type: :string, required: true],
      participant_role: [type: :string, required: true],
      target_id: [type: :string, required: true],
      capability_id: [type: :string, required: true],
      phase: [type: :string, required: true],
      objective: [type: :string, required: true],
      round: [type: :integer, required: true],
      session: [type: :map, default: %{}],
      collaboration_envelope: [type: :map, default: %{}]
    ]

  alias Jido.Agent.StateOp
  alias JidoHiveServer.Collaboration.ExecutionPlan

  @impl true
  def run(params, context) do
    state = context.state
    execution_plan = ExecutionPlan.record_open(state.execution_plan, params.plan_slot_index)

    turn = %{
      job_id: params.job_id,
      plan_slot_index: params.plan_slot_index,
      participant_id: params.participant_id,
      participant_role: params.participant_role,
      target_id: params.target_id,
      capability_id: params.capability_id,
      phase: params.phase,
      objective: params.objective,
      round: params.round,
      session: params.session,
      collaboration_envelope: params.collaboration_envelope,
      status: :running,
      started_at: DateTime.utc_now()
    }

    {:ok, %{},
     StateOp.set_state(%{
       current_turn: turn,
       turns: state.turns ++ [turn],
       execution_plan: execution_plan,
       round: params.round,
       phase: params.phase,
       status: "running"
     })}
  end
end
