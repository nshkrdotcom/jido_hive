defmodule JidoHiveServer.Collaboration.Actions.ApplyResult do
  @moduledoc false

  use Jido.Action,
    name: "apply_result",
    description: "Apply one participant result to room state",
    schema: [
      job_id: [type: :string, required: true],
      participant_id: [type: :string, required: true],
      participant_role: [type: :string, required: true],
      status: [type: :string, default: "completed"],
      summary: [type: :string, default: ""],
      actions: [type: {:list, :map}, default: []],
      tool_events: [type: {:list, :map}, default: []],
      events: [type: {:list, :map}, default: []],
      approvals: [type: {:list, :map}, default: []],
      artifacts: [type: {:list, :map}, default: []],
      execution: [type: :map, default: %{}]
    ]

  alias Jido.Agent.StateOp
  alias JidoHiveServer.Collaboration.Referee

  @impl true
  def run(params, context) do
    state = context.state

    {entries, next_entry_seq} =
      Enum.map_reduce(params.actions, state.next_entry_seq, fn action, seq ->
        entry_type = map_entry_type(action["op"])
        entry_ref = "#{entry_type}:#{seq}"

        entry = %{
          entry_ref: entry_ref,
          entry_type: entry_type,
          job_id: params.job_id,
          participant_id: params.participant_id,
          participant_role: params.participant_role,
          title: action["title"],
          body: action["body"],
          severity: action["severity"],
          targets: action["targets"] || [],
          tool_events: params.tool_events
        }

        {entry, seq + 1}
      end)

    {new_disputes, next_dispute_seq} =
      Enum.reduce(entries, {[], state.next_dispute_seq}, fn entry, {disputes, seq} ->
        if entry.entry_type == "objection" do
          dispute = %{
            dispute_id: "dispute:#{seq}",
            title: entry.title,
            severity: entry.severity,
            status: :open,
            opened_by_entry_ref: entry.entry_ref,
            target_entry_refs: Enum.map(entry.targets, &Map.get(&1, "entry_ref"))
          }

          {[dispute | disputes], seq + 1}
        else
          {disputes, seq}
        end
      end)

    updated_turns = complete_turns(state.turns, params)

    updated_disputes =
      resolve_disputes(state.disputes ++ Enum.reverse(new_disputes), entries, params.job_id)

    updated_state = %{
      state
      | current_turn: %{},
        turns: updated_turns,
        context_entries: state.context_entries ++ entries,
        disputes: updated_disputes,
        next_entry_seq: next_entry_seq,
        next_dispute_seq: next_dispute_seq
    }

    {:ok, %{},
     StateOp.replace_state(%{
       updated_state
       | phase: Referee.phase(updated_state),
         status: room_status(updated_state, params.status)
     })}
  end

  defp map_entry_type("CLAIM"), do: "claim"
  defp map_entry_type("EVIDENCE"), do: "evidence"
  defp map_entry_type("OBJECT"), do: "objection"
  defp map_entry_type("REVISE"), do: "revision"
  defp map_entry_type("DECIDE"), do: "decision"
  defp map_entry_type("PUBLISH"), do: "publish_request"
  defp map_entry_type(_), do: "system_note"

  defp complete_turns(turns, params) do
    Enum.map(turns, fn turn ->
      if turn.job_id == params.job_id do
        Map.merge(turn, %{
          status: turn_status(params.status),
          result_summary: params.summary,
          actions: params.actions,
          tool_events: params.tool_events,
          events: params.events,
          approvals: params.approvals,
          artifacts: params.artifacts,
          execution: params.execution,
          completed_at: DateTime.utc_now()
        })
      else
        turn
      end
    end)
  end

  defp resolve_disputes(disputes, entries, job_id) do
    Enum.reduce(entries, disputes, fn entry, acc ->
      case entry.entry_type do
        type when type in ["revision", "decision"] ->
          resolve_targeted_disputes(acc, entry, job_id)

        _other ->
          acc
      end
    end)
  end

  defp resolve_targeted_disputes(disputes, entry, job_id) do
    targeted_disputes =
      entry.targets
      |> Enum.map(&Map.get(&1, "dispute_id"))
      |> Enum.reject(&is_nil/1)

    Enum.map(disputes, &resolve_dispute(&1, targeted_disputes, entry, job_id))
  end

  defp resolve_dispute(
         %{status: :open, dispute_id: dispute_id} = dispute,
         targeted,
         entry,
         job_id
       ) do
    if dispute_id in targeted do
      Map.merge(dispute, %{
        status: :resolved,
        resolved_by_entry_ref: entry.entry_ref,
        resolved_in_job_id: job_id
      })
    else
      dispute
    end
  end

  defp resolve_dispute(dispute, _targeted, _entry, _job_id), do: dispute

  defp room_status(_updated_state, "failed"), do: "failed"
  defp room_status(updated_state, _status), do: Referee.room_status(updated_state)

  defp turn_status("failed"), do: :failed
  defp turn_status(_status), do: :completed
end
