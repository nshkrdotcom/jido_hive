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
    boundary_sessions = update_boundary_sessions(state, params.target_id, params.session)

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
       boundary_sessions: boundary_sessions,
       round: params.round,
       phase: params.phase,
       status: "running"
     })}
  end

  defp update_boundary_sessions(state, target_id, session) do
    boundary_sessions = Map.get(state, :boundary_sessions, %{})

    case boundary_session_state(session) do
      nil -> boundary_sessions
      boundary_state -> Map.put(boundary_sessions, target_id, boundary_state)
    end
  end

  defp boundary_session_state(session) when is_map(session) do
    case Map.get(session, "boundary") || Map.get(session, :boundary) do
      %{} = boundary ->
        descriptor = Map.get(boundary, "descriptor") || Map.get(boundary, :descriptor) || %{}

        boundary
        |> normalize_map()
        |> Map.put_new(
          "boundary_session_id",
          Map.get(descriptor, "boundary_session_id") || Map.get(descriptor, :boundary_session_id)
        )

      _other ->
        nil
    end
  end

  defp boundary_session_state(_session), do: nil

  defp normalize_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize_value(value)} end)
  end

  defp normalize_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value), do: value
end
