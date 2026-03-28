defmodule JidoHiveServer.Collaboration.Actions.AbandonTurn do
  @moduledoc false

  use Jido.Action,
    name: "abandon_turn",
    description: "Clear a running room turn without consuming the logical turn budget",
    schema: [
      job_id: [type: :string, required: true],
      reason: [type: :string, required: true]
    ]

  alias Jido.Agent.StateOp
  alias JidoHiveServer.Collaboration.{ExecutionPlan, Referee}

  @impl true
  def run(params, context) do
    state = context.state
    abandoned_turn = Enum.find(state.turns, &(&1.job_id == params.job_id))

    turns =
      Enum.map(state.turns, fn turn ->
        if turn.job_id == params.job_id do
          Map.merge(turn, %{
            status: :abandoned,
            result_summary: params.reason,
            execution: %{
              "status" => "abandoned",
              "error" => %{"reason" => params.reason}
            },
            completed_at: DateTime.utc_now()
          })
        else
          turn
        end
      end)

    execution_plan =
      case abandoned_turn do
        %{target_id: target_id} when is_binary(target_id) ->
          ExecutionPlan.record_abandon(state.execution_plan, target_id)

        _other ->
          state.execution_plan
      end

    updated_state = %{state | current_turn: %{}, turns: turns, execution_plan: execution_plan}

    {:ok, %{},
     StateOp.replace_state(%{
       updated_state
       | phase: Referee.phase(updated_state),
         status: Referee.room_status(updated_state)
     })}
  end
end
