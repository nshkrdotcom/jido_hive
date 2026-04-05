defmodule JidoHiveServer.Collaboration.EventReducer do
  @moduledoc false

  alias JidoHiveServer.Collaboration.{ExecutionPlan, Referee}
  alias JidoHiveServer.Collaboration.Schema.RoomEvent

  @max_tracked_event_ids 256

  @spec apply_event(map(), RoomEvent.t()) :: map()
  def apply_event(snapshot, %RoomEvent{} = event) when is_map(snapshot) do
    if applied_event?(snapshot, event.event_id) do
      snapshot
    else
      snapshot
      |> reduce_event(event)
      |> remember_event_id(event.event_id)
    end
  end

  @spec reduce(map(), [RoomEvent.t()]) :: map()
  def reduce(snapshot, events) when is_map(snapshot) and is_list(events) do
    Enum.reduce(events, snapshot, &apply_event(&2, &1))
  end

  defp reduce_event(snapshot, %RoomEvent{type: :room_created, payload: payload}) do
    Map.merge(snapshot, payload)
  end

  defp reduce_event(snapshot, %RoomEvent{type: :turn_opened, payload: payload}) do
    execution_plan = ExecutionPlan.record_open(snapshot.execution_plan, payload.plan_slot_index)

    turn = %{
      job_id: payload.job_id,
      plan_slot_index: payload.plan_slot_index,
      participant_id: payload.participant_id,
      participant_role: payload.participant_role,
      target_id: payload.target_id,
      capability_id: payload.capability_id,
      phase: payload.phase,
      objective: payload.objective,
      round: payload.round,
      session: payload.session || %{},
      collaboration_envelope: payload.collaboration_envelope || %{},
      status: :running,
      started_at:
        Map.get(payload, :started_at) || Map.get(payload, "started_at") || DateTime.utc_now()
    }

    %{
      snapshot
      | current_turn: turn,
        turns: snapshot.turns ++ [turn],
        execution_plan: execution_plan,
        round: payload.round,
        phase: payload.phase,
        status: "running"
    }
  end

  defp reduce_event(snapshot, %RoomEvent{type: type, payload: payload})
       when type in [:turn_completed, :turn_failed] do
    current_turn = Map.get(snapshot, :current_turn, %{})

    if current_turn == %{} or current_turn.job_id != payload.job_id do
      snapshot
    else
      apply_turn_result(snapshot, normalize_result_payload(type, payload))
    end
  end

  defp reduce_event(snapshot, %RoomEvent{type: :turn_abandoned, payload: payload}) do
    abandoned_turn = Enum.find(snapshot.turns, &(&1.job_id == payload.job_id))

    turns =
      Enum.map(snapshot.turns, fn turn ->
        if turn.job_id == payload.job_id do
          Map.merge(turn, %{
            status: :abandoned,
            result_summary: payload.reason,
            execution: %{
              "status" => "abandoned",
              "error" => %{"reason" => payload.reason}
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
          ExecutionPlan.record_abandon(snapshot.execution_plan, target_id)

        _other ->
          snapshot.execution_plan
      end

    updated_state = %{snapshot | current_turn: %{}, turns: turns, execution_plan: execution_plan}

    %{
      updated_state
      | phase: Referee.phase(updated_state),
        status: Referee.room_status(updated_state)
    }
  end

  defp reduce_event(snapshot, %RoomEvent{type: :runtime_state_changed, payload: payload}) do
    %{
      snapshot
      | status: payload.status,
        phase: payload.phase,
        current_turn: Map.get(snapshot, :current_turn, %{})
    }
  end

  defp reduce_event(snapshot, _event), do: snapshot

  defp apply_turn_result(snapshot, payload) do
    {entries, next_entry_seq} =
      Enum.map_reduce(payload.actions, snapshot.next_entry_seq, fn action, seq ->
        entry_type = map_entry_type(action["op"])
        entry_ref = "#{entry_type}:#{seq}"

        entry = %{
          entry_ref: entry_ref,
          entry_type: entry_type,
          job_id: payload.job_id,
          participant_id: payload.participant_id,
          participant_role: payload.participant_role,
          title: action["title"],
          body: action["body"],
          severity: action["severity"],
          targets: action["targets"] || [],
          tool_events: payload.tool_events
        }

        {entry, seq + 1}
      end)

    {new_disputes, next_dispute_seq} =
      Enum.reduce(entries, {[], snapshot.next_dispute_seq}, fn entry, {disputes, seq} ->
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

    updated_turns = complete_turns(snapshot.turns, payload)

    updated_disputes =
      resolve_disputes(snapshot.disputes ++ Enum.reverse(new_disputes), entries, payload.job_id)

    execution_plan = ExecutionPlan.record_completion(snapshot.execution_plan)

    updated_state = %{
      snapshot
      | current_turn: %{},
        turns: updated_turns,
        context_entries: snapshot.context_entries ++ entries,
        disputes: updated_disputes,
        execution_plan: execution_plan,
        next_entry_seq: next_entry_seq,
        next_dispute_seq: next_dispute_seq
    }

    %{
      updated_state
      | phase: Referee.phase(updated_state),
        status: room_status(updated_state, payload.status)
    }
  end

  defp normalize_result_payload(:turn_failed, payload), do: Map.put(payload, :status, "failed")
  defp normalize_result_payload(_type, payload), do: payload

  defp complete_turns(turns, payload) do
    Enum.map(turns, fn turn ->
      if turn.job_id == payload.job_id do
        Map.merge(turn, %{
          status: turn_status(payload.status),
          result_summary: payload.summary,
          actions: payload.actions,
          tool_events: payload.tool_events,
          events: payload.events,
          approvals: payload.approvals,
          artifacts: payload.artifacts,
          execution: payload.execution,
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

  defp map_entry_type("CLAIM"), do: "claim"
  defp map_entry_type("EVIDENCE"), do: "evidence"
  defp map_entry_type("OBJECT"), do: "objection"
  defp map_entry_type("REVISE"), do: "revision"
  defp map_entry_type("DECIDE"), do: "decision"
  defp map_entry_type("PUBLISH"), do: "publish_request"
  defp map_entry_type(_), do: "system_note"

  defp room_status(_updated_state, "failed"), do: "failed"
  defp room_status(updated_state, _status), do: Referee.room_status(updated_state)

  defp turn_status("failed"), do: :failed
  defp turn_status(_status), do: :completed

  defp applied_event?(snapshot, event_id) when is_binary(event_id) do
    snapshot
    |> workflow_state()
    |> Map.get(:applied_event_ids, [])
    |> Enum.member?(event_id)
  end

  defp applied_event?(_snapshot, _event_id), do: false

  defp remember_event_id(snapshot, nil), do: snapshot

  defp remember_event_id(snapshot, event_id) do
    ids =
      snapshot
      |> workflow_state()
      |> Map.get(:applied_event_ids, [])
      |> Kernel.++([event_id])
      |> Enum.uniq()
      |> Enum.take(-@max_tracked_event_ids)

    put_in(snapshot, [:workflow_state, :applied_event_ids], ids)
  end

  defp workflow_state(snapshot) do
    snapshot
    |> Map.get(:workflow_state, %{})
    |> Map.new(fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      pair -> pair
    end)
  end
end
