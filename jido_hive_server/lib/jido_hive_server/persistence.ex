defmodule JidoHiveServer.Persistence do
  @moduledoc false

  import Ecto.Query

  alias JidoHiveServer.Collaboration.Schema.RoomEvent
  alias JidoHiveServer.Collaboration.SnapshotProjection

  alias JidoHiveServer.Persistence.{
    PublicationRunRecord,
    RoomEventRecord,
    RoomSnapshotRecord,
    TargetRecord
  }

  alias JidoHiveServer.Repo

  @spec persist_room_snapshot(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def persist_room_snapshot(%{room_id: room_id} = snapshot) when is_binary(room_id) do
    attrs = %{
      room_id: room_id,
      snapshot: snapshot |> SnapshotProjection.strip_derived() |> normalize()
    }

    %RoomSnapshotRecord{}
    |> RoomSnapshotRecord.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: [snapshot: attrs.snapshot, updated_at: DateTime.utc_now()]],
      conflict_target: :room_id
    )
    |> case do
      {:ok, record} -> {:ok, rehydrate_room_snapshot(record.snapshot)}
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

  @spec delete_room_events(String.t()) :: :ok
  def delete_room_events(room_id) when is_binary(room_id) do
    from(record in RoomEventRecord, where: record.room_id == ^room_id)
    |> Repo.delete_all()

    :ok
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
      {:ok, record} -> {:ok, rehydrate_target(record.snapshot)}
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

  @spec append_room_events(String.t(), [RoomEvent.t()]) :: :ok | {:error, term()}
  def append_room_events(room_id, events) when is_binary(room_id) and is_list(events) do
    Repo.transaction(fn ->
      Enum.each(events, fn %RoomEvent{} = event ->
        attrs = %{
          event_id: event.event_id,
          room_id: room_id,
          event_type: Atom.to_string(event.type),
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          payload: normalize(event.payload || %{})
        }

        %RoomEventRecord{}
        |> RoomEventRecord.changeset(attrs)
        |> Repo.insert!()
      end)
    end)
    |> case do
      {:ok, _value} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @spec list_room_events(String.t()) :: [RoomEvent.t()]
  def list_room_events(room_id) when is_binary(room_id) do
    from(record in RoomEventRecord,
      where: record.room_id == ^room_id,
      order_by: [asc: record.inserted_at, asc: record.id]
    )
    |> Repo.all()
    |> Enum.map(&rehydrate_room_event/1)
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
      current_assignment: snapshot_map(snapshot, "current_assignment", &rehydrate_assignment/1),
      assignments: snapshot_list(snapshot, "assignments", &rehydrate_assignment/1),
      context_objects: snapshot_list(snapshot, "context_objects", &rehydrate_context_object/1),
      contributions: snapshot_list(snapshot, "contributions", &rehydrate_contribution/1),
      context_config: rehydrate_context_config(snapshot_map(snapshot, "context_config", & &1)),
      dispatch_policy_id: snapshot_value(snapshot, "dispatch_policy_id", "round_robin/v2"),
      dispatch_policy_config: snapshot_map(snapshot, "dispatch_policy_config", & &1),
      dispatch_state: rehydrate_dispatch_state(snapshot_map(snapshot, "dispatch_state", & &1)),
      status: snapshot_value(snapshot, "status", "idle"),
      next_context_seq: snapshot_value(snapshot, "next_context_seq", 1),
      next_assignment_seq: snapshot_value(snapshot, "next_assignment_seq", 1),
      next_contribution_seq: snapshot_value(snapshot, "next_contribution_seq", 1)
    }
    |> SnapshotProjection.project()
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
      execution_surface: snapshot["execution_surface"],
      execution_environment: snapshot["execution_environment"],
      provider_options: snapshot["provider_options"],
      status: snapshot["status"]
    }
  end

  defp rehydrate_participant(participant) do
    %{
      participant_id: participant["participant_id"],
      participant_role: participant["participant_role"],
      participant_kind: participant["participant_kind"],
      authority_level: participant["authority_level"],
      target_id: participant["target_id"],
      capability_id: participant["capability_id"],
      provider: participant["provider"],
      runtime_driver: participant["runtime_driver"],
      workspace_root: participant["workspace_root"],
      metadata: participant["metadata"] || %{}
    }
  end

  defp rehydrate_assignment(assignment) when map_size(assignment) == 0, do: %{}

  defp rehydrate_assignment(assignment) do
    %{
      assignment_id: assignment["assignment_id"],
      room_id: assignment["room_id"],
      participant_id: assignment["participant_id"],
      participant_role: assignment["participant_role"],
      target_id: assignment["target_id"],
      capability_id: assignment["capability_id"],
      phase: assignment["phase"],
      objective: assignment["objective"],
      contribution_contract: assignment["contribution_contract"] || %{},
      context_view: assignment["context_view"] || %{},
      plan_slot_index: assignment["plan_slot_index"] || 0,
      status: assignment["status"],
      task_context: assignment["task_context"] || %{},
      opened_at: datetime_value(assignment["opened_at"]),
      completed_at: datetime_value(assignment["completed_at"]),
      session: assignment["session"] || %{},
      result_summary: assignment["result_summary"]
    }
  end

  defp rehydrate_context_object(context_object) do
    %{
      context_id: context_object["context_id"],
      object_type: context_object["object_type"],
      title: context_object["title"],
      body: context_object["body"],
      data: context_object["data"] || %{},
      authored_by: context_object["authored_by"] || %{},
      provenance: context_object["provenance"] || %{},
      scope: rehydrate_scope(context_object["scope"] || %{}),
      uncertainty: rehydrate_uncertainty(context_object["uncertainty"] || %{}),
      relations: context_object["relations"] || [],
      inserted_at: datetime_value(context_object["inserted_at"])
    }
  end

  defp rehydrate_contribution(contribution) do
    %{
      contribution_id: contribution["contribution_id"],
      room_id: contribution["room_id"],
      assignment_id: contribution["assignment_id"],
      participant_id: contribution["participant_id"],
      participant_role: contribution["participant_role"],
      participant_kind: contribution["participant_kind"],
      target_id: contribution["target_id"],
      capability_id: contribution["capability_id"],
      contribution_type: contribution["contribution_type"],
      authority_level: contribution["authority_level"],
      summary: contribution["summary"],
      consumed_context_ids: contribution["consumed_context_ids"] || [],
      context_objects: contribution["context_objects"] || [],
      artifacts: contribution["artifacts"] || [],
      events: contribution["events"] || [],
      tool_events: contribution["tool_events"] || [],
      approvals: contribution["approvals"] || [],
      execution: contribution["execution"] || %{},
      status: contribution["status"],
      schema_version: contribution["schema_version"]
    }
  end

  defp rehydrate_dispatch_state(dispatch_state) do
    %{
      applied_event_ids: dispatch_state["applied_event_ids"] || [],
      completed_slots: dispatch_state["completed_slots"] || 0,
      total_slots: dispatch_state["total_slots"] || 0,
      participant_ids: dispatch_state["participant_ids"] || [],
      phases: dispatch_state["phases"] || []
    }
  end

  defp rehydrate_context_config(context_config) do
    participant_scopes =
      context_config
      |> Map.get("participant_scopes", %{})
      |> Map.new(fn {participant_id, scope} ->
        {participant_id,
         %{
           writable_types: rehydrate_dimension(scope["writable_types"]),
           writable_node_ids: rehydrate_dimension(scope["writable_node_ids"]),
           reference_hop_limit: scope["reference_hop_limit"] || 2
         }}
      end)

    %{participant_scopes: participant_scopes}
  end

  defp rehydrate_dimension("all"), do: :all
  defp rehydrate_dimension(nil), do: :all
  defp rehydrate_dimension(values) when is_list(values), do: values
  defp rehydrate_dimension(_values), do: :all

  defp rehydrate_scope(scope) do
    %{
      read: scope["read"] || [],
      write: scope["write"] || []
    }
  end

  defp rehydrate_uncertainty(uncertainty) do
    %{
      status: uncertainty["status"],
      confidence: uncertainty["confidence"],
      rationale: uncertainty["rationale"]
    }
  end

  defp rehydrate_room_event(%RoomEventRecord{} = record) do
    {:ok, event} =
      RoomEvent.new(%{
        event_id: record.event_id,
        room_id: record.room_id,
        type: record.event_type,
        payload: record.payload || %{},
        causation_id: record.causation_id,
        correlation_id: record.correlation_id,
        recorded_at: record.inserted_at
      })

    event
  end

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

  defp datetime_value(nil), do: nil
  defp datetime_value(%DateTime{} = value), do: value

  defp datetime_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp datetime_value(_value), do: nil

  defp normalize(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize()
  end

  defp normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {normalize_key(key), normalize(value)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(nil), do: nil
  defp normalize(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key
end
