defmodule JidoHiveServer.Collaboration.Envelope do
  @moduledoc false

  alias JidoHiveServer.Collaboration.Referee

  @schema_version "jido_hive/collab_envelope.v1"

  @spec build(map(), map()) :: map()
  def build(snapshot, assignment) when is_map(snapshot) and is_map(assignment) do
    %{
      "schema_version" => @schema_version,
      "room" => %{
        "room_id" => snapshot.room_id,
        "brief" => snapshot.brief,
        "rules" => snapshot.rules,
        "status" => snapshot.status
      },
      "referee" => %{
        "phase" => assignment.phase,
        "directives" => assignment.directives,
        "open_disputes" => Enum.map(assignment.open_disputes || [], &public_dispute/1),
        "publish_requested" => Referee.publish_requested?(snapshot)
      },
      "turn" => %{
        "phase" => assignment.phase,
        "round" => assignment.round,
        "participant_id" => assignment.participant_id,
        "participant_role" => assignment.participant_role,
        "objective" => assignment.objective,
        "response_contract" => response_contract()
      },
      "shared" => %{
        "entries" => Enum.map(snapshot.context_entries, &public_entry/1),
        "instruction_log" => instruction_log(snapshot.turns),
        "tool_call_log" => tool_call_log(snapshot.turns),
        "artifact_log" => artifact_log(snapshot.turns)
      }
    }
  end

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  defp response_contract do
    %{
      "format" => "json_object",
      "allowed_ops" => ["CLAIM", "EVIDENCE", "OBJECT", "REVISE", "DECIDE", "PUBLISH"],
      "target_kinds" => ["entry_ref", "dispute_id"]
    }
  end

  defp instruction_log(turns) do
    Enum.map(turns, fn turn ->
      %{
        "job_id" => turn.job_id,
        "phase" => Map.get(turn, :phase),
        "participant_role" => Map.get(turn, :participant_role),
        "objective" => Map.get(turn, :objective),
        "summary" => Map.get(turn, :result_summary, "turn queued")
      }
    end)
  end

  defp tool_call_log(turns) do
    Enum.flat_map(turns, fn turn ->
      turn
      |> Map.get(:tool_events, [])
      |> Enum.map(fn event ->
        %{
          "job_id" => turn.job_id,
          "participant_role" => Map.get(turn, :participant_role),
          "event_type" => event["event_type"],
          "payload" => event["payload"]
        }
      end)
    end)
  end

  defp artifact_log(turns) do
    Enum.flat_map(turns, fn turn ->
      turn
      |> Map.get(:artifacts, [])
      |> Enum.map(fn artifact ->
        %{
          "job_id" => turn.job_id,
          "participant_role" => Map.get(turn, :participant_role),
          "artifact_type" => artifact["artifact_type"],
          "title" => artifact["title"],
          "body" => artifact["body"]
        }
      end)
    end)
  end

  defp public_entry(entry) do
    %{
      "entry_ref" => entry.entry_ref,
      "entry_type" => entry.entry_type,
      "participant_role" => entry.participant_role,
      "title" => entry.title,
      "body" => entry.body,
      "severity" => entry.severity,
      "targets" => entry.targets || []
    }
  end

  defp public_dispute(dispute) do
    %{
      "dispute_id" => dispute.dispute_id,
      "title" => dispute.title,
      "status" => Atom.to_string(dispute.status),
      "severity" => dispute.severity,
      "target_entry_refs" => dispute.target_entry_refs || [],
      "opened_by_entry_ref" => dispute.opened_by_entry_ref
    }
  end
end
