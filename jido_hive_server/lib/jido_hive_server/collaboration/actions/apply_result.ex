defmodule JidoHiveServer.Collaboration.Actions.ApplyResult do
  @moduledoc false

  use Jido.Action,
    name: "apply_result",
    description: "Apply one participant result to room state",
    schema: [
      job_id: [type: :string, required: true],
      participant_id: [type: :string, required: true],
      participant_role: [type: :string, required: true],
      summary: [type: :string, default: ""],
      actions: [type: {:list, :map}, default: []],
      tool_events: [type: {:list, :map}, default: []]
    ]

  alias Jido.Agent.StateOp

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
            status: :open,
            opened_by_entry_id: entry.entry_ref
          }

          {[dispute | disputes], seq + 1}
        else
          {disputes, seq}
        end
      end)

    updated_turns =
      case Enum.split(state.turns, -1) do
        {existing, [last_turn]} ->
          existing ++
            [
              Map.merge(last_turn, %{
                status: :completed,
                result_summary: params.summary,
                actions: params.actions,
                tool_events: params.tool_events
              })
            ]

        {_existing, []} ->
          state.turns
      end

    {:ok, %{},
     StateOp.replace_state(%{
       state
       | current_turn: %{},
         turns: updated_turns,
         context_entries: state.context_entries ++ entries,
         disputes: state.disputes ++ Enum.reverse(new_disputes),
         next_entry_seq: next_entry_seq,
         next_dispute_seq: next_dispute_seq,
         status: "idle"
     })}
  end

  defp map_entry_type("CLAIM"), do: "claim"
  defp map_entry_type("EVIDENCE"), do: "evidence"
  defp map_entry_type("OBJECT"), do: "objection"
  defp map_entry_type("REVISE"), do: "revision"
  defp map_entry_type("DECIDE"), do: "decision"
  defp map_entry_type("PUBLISH"), do: "publish_request"
  defp map_entry_type(_), do: "system_note"
end
