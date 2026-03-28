defmodule JidoHiveServer.Persistence do
  @moduledoc false

  import Ecto.Query

  alias JidoHiveServer.Persistence.{PublicationRunRecord, RoomSnapshotRecord, TargetRecord}
  alias JidoHiveServer.Repo

  @spec persist_room_snapshot(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def persist_room_snapshot(%{room_id: room_id} = snapshot) when is_binary(room_id) do
    attrs = %{room_id: room_id, snapshot: normalize(snapshot)}

    %RoomSnapshotRecord{}
    |> RoomSnapshotRecord.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: [snapshot: attrs.snapshot, updated_at: DateTime.utc_now()]],
      conflict_target: :room_id
    )
    |> case do
      {:ok, record} -> {:ok, record.snapshot}
      {:error, _} = error -> error
    end
  end

  @spec fetch_room_snapshot(String.t()) :: {:ok, map()} | {:error, :room_not_found}
  def fetch_room_snapshot(room_id) when is_binary(room_id) do
    case Repo.get(RoomSnapshotRecord, room_id) do
      %RoomSnapshotRecord{snapshot: snapshot} -> {:ok, rehydrate_room_snapshot(snapshot)}
      nil -> {:error, :room_not_found}
    end
  end

  @spec upsert_target(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def upsert_target(%{target_id: target_id} = target) when is_binary(target_id) do
    normalized =
      target
      |> Map.drop([:channel_pid])
      |> normalize()

    attrs =
      normalized
      |> Map.take([
        "target_id",
        "workspace_id",
        "participant_id",
        "participant_role",
        "capability_id",
        "runtime_driver",
        "provider",
        "workspace_root"
      ])
      |> Map.put("snapshot", normalized)
      |> Map.put("status", "online")

    %TargetRecord{}
    |> TargetRecord.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          workspace_id: attrs["workspace_id"],
          participant_id: attrs["participant_id"],
          participant_role: attrs["participant_role"],
          capability_id: attrs["capability_id"],
          runtime_driver: attrs["runtime_driver"],
          provider: attrs["provider"],
          workspace_root: attrs["workspace_root"],
          snapshot: attrs["snapshot"],
          status: "online",
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :target_id
    )
    |> case do
      {:ok, record} -> {:ok, record.snapshot}
      {:error, _} = error -> error
    end
  end

  @spec fetch_target(String.t()) :: {:ok, map()} | {:error, :target_not_found}
  def fetch_target(target_id) when is_binary(target_id) do
    case Repo.get(TargetRecord, target_id) do
      %TargetRecord{snapshot: snapshot} -> {:ok, rehydrate_target(snapshot)}
      nil -> {:error, :target_not_found}
    end
  end

  @spec mark_target_offline(String.t()) :: :ok
  def mark_target_offline(target_id) when is_binary(target_id) do
    from(record in TargetRecord, where: record.target_id == ^target_id)
    |> Repo.update_all(set: [status: "offline", updated_at: DateTime.utc_now()])

    :ok
  end

  @spec mark_all_targets_offline() :: :ok
  def mark_all_targets_offline do
    try do
      from(record in TargetRecord)
      |> Repo.update_all(set: [status: "offline", updated_at: DateTime.utc_now()])
    rescue
      _error -> :ok
    end

    :ok
  end

  @spec list_targets(keyword()) :: [map()]
  def list_targets(opts \\ []) do
    status = Keyword.get(opts, :status)

    TargetRecord
    |> maybe_filter_status(status)
    |> order_by([record], asc: record.participant_role, asc: record.target_id)
    |> Repo.all()
    |> Enum.map(&rehydrate_target(&1.snapshot))
  end

  @spec create_publication_run(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def create_publication_run(attrs) when is_map(attrs) do
    normalized = normalize(attrs)

    %PublicationRunRecord{}
    |> PublicationRunRecord.changeset(normalized)
    |> Repo.insert()
    |> case do
      {:ok, record} -> {:ok, publication_run_snapshot(record)}
      {:error, _} = error -> error
    end
  end

  @spec update_publication_run(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_publication_run(publication_run_id, attrs)
      when is_binary(publication_run_id) and is_map(attrs) do
    case Repo.get(PublicationRunRecord, publication_run_id) do
      nil ->
        {:error, :publication_run_not_found}

      %PublicationRunRecord{} = record ->
        record
        |> PublicationRunRecord.changeset(normalize(attrs))
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, publication_run_snapshot(updated)}
          {:error, _} = error -> error
        end
    end
  end

  @spec list_publication_runs(String.t()) :: [map()]
  def list_publication_runs(room_id) when is_binary(room_id) do
    from(record in PublicationRunRecord,
      where: record.room_id == ^room_id,
      order_by: [asc: record.inserted_at, asc: record.publication_run_id]
    )
    |> Repo.all()
    |> Enum.map(&publication_run_snapshot/1)
  end

  defp publication_run_snapshot(%PublicationRunRecord{} = record) do
    %{
      publication_run_id: record.publication_run_id,
      room_id: record.room_id,
      channel: record.channel,
      connector_id: record.connector_id,
      capability_id: record.capability_id,
      status: record.status,
      request: record.request || %{},
      result: record.result || %{},
      error: record.error || %{},
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    }
  end

  defp rehydrate_room_snapshot(snapshot) when is_map(snapshot) do
    %{
      room_id: snapshot_value(snapshot, "room_id"),
      session_id: snapshot_value(snapshot, "session_id"),
      brief: snapshot_value(snapshot, "brief"),
      rules: snapshot_list(snapshot, "rules"),
      participants: snapshot_list(snapshot, "participants", &rehydrate_participant/1),
      turns: snapshot_list(snapshot, "turns", &rehydrate_turn/1),
      context_entries: snapshot_list(snapshot, "context_entries", &rehydrate_context_entry/1),
      disputes: snapshot_list(snapshot, "disputes", &rehydrate_dispute/1),
      current_turn: snapshot_map(snapshot, "current_turn", &rehydrate_turn_map/1),
      execution_plan: snapshot_map(snapshot, "execution_plan", &rehydrate_execution_plan/1),
      status: snapshot_value(snapshot, "status", "idle"),
      phase: snapshot_value(snapshot, "phase", "idle"),
      round: snapshot_value(snapshot, "round", 0),
      next_entry_seq: snapshot_value(snapshot, "next_entry_seq", 1),
      next_dispute_seq: snapshot_value(snapshot, "next_dispute_seq", 1)
    }
  end

  defp rehydrate_target(snapshot) when is_map(snapshot) do
    %{
      target_id: snapshot["target_id"],
      capability_id: snapshot["capability_id"],
      workspace_id: snapshot["workspace_id"],
      user_id: snapshot["user_id"],
      participant_id: snapshot["participant_id"],
      participant_role: snapshot["participant_role"],
      runtime_driver: snapshot["runtime_driver"],
      provider: snapshot["provider"],
      workspace_root: snapshot["workspace_root"],
      status: snapshot["status"]
    }
  end

  defp rehydrate_participant(participant) do
    %{
      participant_id: participant["participant_id"],
      role: participant["role"],
      target_id: participant["target_id"],
      capability_id: participant["capability_id"]
    }
  end

  defp rehydrate_turn(turn) do
    turn
    |> rehydrate_turn_map()
    |> Map.merge(%{
      collaboration_envelope: turn["collaboration_envelope"] || %{},
      session: turn["session"] || %{},
      actions: turn["actions"] || [],
      tool_events: turn["tool_events"] || [],
      events: turn["events"] || [],
      approvals: turn["approvals"] || [],
      artifacts: turn["artifacts"] || [],
      execution: turn["execution"] || %{}
    })
  end

  defp rehydrate_turn_map(turn) when map_size(turn) == 0, do: %{}

  defp rehydrate_turn_map(turn) do
    %{
      job_id: turn["job_id"],
      plan_slot_index: turn["plan_slot_index"],
      participant_id: turn["participant_id"],
      participant_role: turn["participant_role"],
      target_id: turn["target_id"],
      capability_id: turn["capability_id"],
      phase: turn["phase"],
      objective: turn["objective"],
      round: turn["round"],
      status: rehydrate_status(turn["status"]),
      started_at: turn["started_at"],
      completed_at: turn["completed_at"],
      result_summary: turn["result_summary"]
    }
  end

  defp rehydrate_execution_plan(plan) when map_size(plan) == 0, do: %{}

  defp rehydrate_execution_plan(plan) do
    %{
      strategy: plan["strategy"],
      max_participants: plan["max_participants"],
      stage_count: plan["stage_count"],
      participant_count: plan["participant_count"],
      planned_turn_count: plan["planned_turn_count"],
      completed_turn_count: plan["completed_turn_count"],
      round_robin_index: plan["round_robin_index"],
      excluded_target_ids: plan["excluded_target_ids"] || [],
      started_at: plan["started_at"],
      locked_participants: snapshot_list(plan, "locked_participants", &rehydrate_participant/1)
    }
  end

  defp rehydrate_context_entry(entry) do
    %{
      entry_ref: entry["entry_ref"],
      entry_type: entry["entry_type"],
      job_id: entry["job_id"],
      participant_id: entry["participant_id"],
      participant_role: entry["participant_role"],
      title: entry["title"],
      body: entry["body"],
      severity: entry["severity"],
      targets: entry["targets"] || [],
      tool_events: entry["tool_events"] || []
    }
  end

  defp rehydrate_dispute(dispute) do
    %{
      dispute_id: dispute["dispute_id"],
      title: dispute["title"],
      severity: dispute["severity"],
      status: rehydrate_status(dispute["status"]),
      opened_by_entry_ref: dispute["opened_by_entry_ref"],
      target_entry_refs: dispute["target_entry_refs"] || [],
      resolved_by_entry_ref: dispute["resolved_by_entry_ref"],
      resolved_in_job_id: dispute["resolved_in_job_id"]
    }
  end

  defp rehydrate_status(nil), do: nil
  defp rehydrate_status(value) when is_atom(value), do: value
  defp rehydrate_status(value) when is_binary(value), do: String.to_atom(value)

  defp snapshot_value(snapshot, key, default \\ nil), do: Map.get(snapshot, key, default)

  defp snapshot_list(snapshot, key, mapper \\ & &1) do
    snapshot
    |> Map.get(key, [])
    |> Enum.map(mapper)
  end

  defp snapshot_map(snapshot, key, mapper) do
    snapshot
    |> Map.get(key, %{})
    |> mapper.()
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status),
    do: from(record in query, where: record.status == ^status)

  defp normalize(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize()
  end

  defp normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {normalize_key(key), normalize(value)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key
end
