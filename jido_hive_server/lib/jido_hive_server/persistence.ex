defmodule JidoHiveServer.Persistence do
  @moduledoc false

  import Ecto.Query

  alias JidoHiveServer.Collaboration.Schema.{
    Assignment,
    Contribution,
    RoomEvent,
    RoomSnapshot
  }

  alias JidoHiveServer.Persistence.{
    RoomEventRecord,
    RoomRunRecord,
    RoomSnapshotRecord,
    TargetRecord
  }

  alias JidoHiveServer.Repo

  @default_contribution_window 200

  @spec persist_room_transition(String.t(), [RoomEvent.t()], RoomSnapshot.t(), list()) ::
          {:ok, RoomSnapshot.t()} | {:error, term()}
  def persist_room_transition(room_id, events, %RoomSnapshot{} = snapshot, _run_updates \\ [])
      when is_binary(room_id) and is_list(events) do
    compacted_snapshot = compact_snapshot(snapshot)
    snapshot_attrs = room_snapshot_attrs(compacted_snapshot)

    Repo.transaction(fn ->
      Enum.each(events, fn %RoomEvent{} = event ->
        room_id
        |> room_event_attrs(event)
        |> insert_room_event_record()
      end)

      %RoomSnapshotRecord{}
      |> RoomSnapshotRecord.changeset(snapshot_attrs)
      |> Repo.insert(
        on_conflict: [set: [snapshot: snapshot_attrs.snapshot, updated_at: DateTime.utc_now()]],
        conflict_target: :room_id
      )
      |> case do
        {:ok, _record} -> compacted_snapshot
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, persisted_snapshot} -> {:ok, persisted_snapshot}
      {:error, error} -> {:error, error}
    end
  end

  @spec persist_room_snapshot(RoomSnapshot.t()) :: {:ok, RoomSnapshot.t()} | {:error, term()}
  def persist_room_snapshot(%RoomSnapshot{} = snapshot) do
    compacted_snapshot = compact_snapshot(snapshot)
    attrs = room_snapshot_attrs(compacted_snapshot)

    %RoomSnapshotRecord{}
    |> RoomSnapshotRecord.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: [snapshot: attrs.snapshot, updated_at: DateTime.utc_now()]],
      conflict_target: :room_id
    )
    |> case do
      {:ok, _record} -> {:ok, compacted_snapshot}
      {:error, _changeset} = error -> error
    end
  end

  @spec fetch_room_snapshot(String.t()) ::
          {:ok, RoomSnapshot.t()} | {:error, :room_not_found | :invalid_snapshot_format}
  def fetch_room_snapshot(room_id) when is_binary(room_id) do
    case Repo.get(RoomSnapshotRecord, room_id) do
      %RoomSnapshotRecord{snapshot: snapshot} ->
        rehydrate_room_snapshot(snapshot)

      nil ->
        {:error, :room_not_found}
    end
  end

  @spec list_rooms(keyword()) :: {:ok, [RoomSnapshot.t()]} | {:error, term()}
  def list_rooms(opts \\ []) do
    limit = Keyword.get(opts, :limit)
    participant_id = Keyword.get(opts, :participant_id)
    status = Keyword.get(opts, :status)

    RoomSnapshotRecord
    |> order_by([record], asc: record.room_id)
    |> maybe_limit(limit)
    |> Repo.all()
    |> Enum.reduce_while({:ok, []}, fn %RoomSnapshotRecord{snapshot: snapshot}, {:ok, acc} ->
      reduce_room_snapshot(snapshot, acc, participant_id, status)
    end)
  end

  @spec delete_room_events(String.t()) :: :ok
  def delete_room_events(room_id) when is_binary(room_id) do
    from(record in RoomEventRecord, where: record.room_id == ^room_id)
    |> Repo.delete_all()

    :ok
  end

  @spec append_room_events(String.t(), [RoomEvent.t()]) :: :ok | {:error, term()}
  def append_room_events(room_id, events) when is_binary(room_id) and is_list(events) do
    Repo.transaction(fn ->
      Enum.each(events, fn %RoomEvent{} = event ->
        room_id
        |> room_event_attrs(event)
        |> insert_room_event_record()
      end)
    end)
    |> case do
      {:ok, _value} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @spec list_room_events(String.t(), keyword()) :: {:ok, [RoomEvent.t()]} | {:error, term()}
  def list_room_events(room_id, opts \\ []) when is_binary(room_id) and is_list(opts) do
    after_sequence = Keyword.get(opts, :after_sequence, 0)
    limit = Keyword.get(opts, :limit)
    list_room_events_after(room_id, after_sequence, limit: limit)
  end

  @spec list_room_events_after(String.t(), non_neg_integer(), keyword()) ::
          {:ok, [RoomEvent.t()]} | {:error, term()}
  def list_room_events_after(room_id, checkpoint_sequence, opts \\ [])
      when is_binary(room_id) and is_integer(checkpoint_sequence) and checkpoint_sequence >= 0 do
    limit = Keyword.get(opts, :limit)

    RoomEventRecord
    |> where([record], record.room_id == ^room_id and record.sequence > ^checkpoint_sequence)
    |> order_by([record], asc: record.sequence)
    |> maybe_limit(limit)
    |> Repo.all()
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, acc} ->
      case rehydrate_room_event(record) do
        {:ok, event} -> {:cont, {:ok, acc ++ [event]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec list_contributions(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_contributions(room_id, opts \\ []) when is_binary(room_id) and is_list(opts) do
    after_sequence = Keyword.get(opts, :after_sequence, 0)
    limit = Keyword.get(opts, :limit)
    participant_id = Keyword.get(opts, :participant_id)
    assignment_id = Keyword.get(opts, :assignment_id)
    kind = Keyword.get(opts, :kind)

    with {:ok, events} <- list_room_events_after(room_id, after_sequence, []) do
      contributions =
        events
        |> Enum.filter(&(&1.type == :contribution_submitted))
        |> Enum.map(fn event ->
          %{
            event_sequence: event.sequence,
            contribution:
              event.data
              |> Map.get("contribution", event.data)
              |> then(fn contribution_data ->
                case Contribution.new(contribution_data) do
                  {:ok, contribution} -> contribution
                  {:error, _reason} -> nil
                end
              end)
          }
        end)
        |> Enum.reject(&is_nil(&1.contribution))
        |> Enum.filter(
          &matches_contribution_filters?(&1.contribution, participant_id, assignment_id, kind)
        )
        |> maybe_take(limit)

      {:ok, contributions}
    end
  end

  @spec create_room_run(map()) :: {:ok, map()} | {:error, term()}
  def create_room_run(attrs) when is_map(attrs) do
    normalized = normalize(attrs)

    %RoomRunRecord{}
    |> RoomRunRecord.changeset(normalized)
    |> Repo.insert()
    |> case do
      {:ok, record} -> {:ok, room_run_snapshot(record)}
      {:error, _changeset} = error -> error
    end
  end

  @spec update_room_run(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_room_run(run_id, attrs) when is_binary(run_id) and is_map(attrs) do
    case Repo.get(RoomRunRecord, run_id) do
      nil ->
        {:error, :room_run_not_found}

      %RoomRunRecord{} = record ->
        record
        |> RoomRunRecord.changeset(normalize(attrs))
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, room_run_snapshot(updated)}
          {:error, _changeset} = error -> error
        end
    end
  end

  @spec fetch_room_run(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_room_run(room_id, run_id) when is_binary(room_id) and is_binary(run_id) do
    case Repo.get(RoomRunRecord, run_id) do
      %RoomRunRecord{room_id: ^room_id} = record -> {:ok, room_run_snapshot(record)}
      %RoomRunRecord{} -> {:error, :room_run_not_found}
      nil -> {:error, :room_run_not_found}
    end
  end

  @spec list_room_runs(String.t()) :: {:ok, [map()]} | {:error, term()}
  def list_room_runs(room_id) when is_binary(room_id) do
    runs =
      from(record in RoomRunRecord,
        where: record.room_id == ^room_id,
        order_by: [asc: record.inserted_at, asc: record.run_id]
      )
      |> Repo.all()
      |> Enum.map(&room_run_snapshot/1)

    {:ok, runs}
  end

  @spec list_active_room_runs(String.t()) :: {:ok, [map()]} | {:error, term()}
  def list_active_room_runs(room_id) when is_binary(room_id) do
    runs =
      from(record in RoomRunRecord,
        where: record.room_id == ^room_id and record.status in ["queued", "running"],
        order_by: [asc: record.inserted_at, asc: record.run_id]
      )
      |> Repo.all()
      |> Enum.map(&room_run_snapshot/1)

    {:ok, runs}
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

  defp room_snapshot_attrs(%RoomSnapshot{} = snapshot) do
    %{
      room_id: snapshot.room.id,
      snapshot: snapshot |> RoomSnapshot.to_map() |> normalize()
    }
  end

  defp room_event_attrs(room_id, %RoomEvent{} = event) do
    %{
      event_id: event.id,
      room_id: room_id,
      sequence: event.sequence,
      event_type: Atom.to_string(event.type),
      payload: normalize(event.data),
      causation_id: nil,
      correlation_id: nil
    }
  end

  defp insert_room_event_record(attrs) do
    %RoomEventRecord{}
    |> RoomEventRecord.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :event_id)
    |> case do
      {:ok, _record} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp rehydrate_room_snapshot(snapshot) when is_map(snapshot) do
    if RoomSnapshot.valid_snapshot_map?(snapshot) do
      RoomSnapshot.new(snapshot)
    else
      {:error, :invalid_snapshot_format}
    end
  end

  defp rehydrate_room_event(%RoomEventRecord{} = record) do
    RoomEvent.new(%{
      id: record.event_id,
      room_id: record.room_id,
      sequence: record.sequence,
      type: record.event_type,
      data: record.payload || %{},
      inserted_at: record.inserted_at
    })
  end

  defp room_run_snapshot(%RoomRunRecord{} = record) do
    %{
      id: record.run_id,
      room_id: record.room_id,
      status: record.status,
      max_assignments: record.max_assignments,
      assignments_started: record.assignments_started,
      assignments_completed: record.assignments_completed,
      assignment_timeout_ms: record.assignment_timeout_ms,
      until: record.until || %{},
      result: record.result,
      error: record.error,
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
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
      execution_surface: snapshot["execution_surface"],
      execution_environment: snapshot["execution_environment"],
      provider_options: snapshot["provider_options"],
      status: snapshot["status"]
    }
  end

  defp compact_snapshot(%RoomSnapshot{} = snapshot) do
    retained_assignment_ids =
      snapshot.assignments
      |> Enum.reject(&Assignment.terminal_status?/1)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    recent = Enum.take(snapshot.contributions, -@default_contribution_window)

    referenced =
      Enum.filter(snapshot.contributions, fn contribution ->
        is_binary(contribution.assignment_id) and
          MapSet.member?(retained_assignment_ids, contribution.assignment_id)
      end)

    contributions =
      recent
      |> Kernel.++(referenced)
      |> Enum.uniq_by(& &1.id)

    %{snapshot | contributions: contributions}
  end

  defp room_matches?(%RoomSnapshot{} = _snapshot, nil, nil), do: true

  defp room_matches?(%RoomSnapshot{} = snapshot, participant_id, status) do
    participant_match? =
      case participant_id do
        nil -> true
        value -> Enum.any?(snapshot.participants, &(&1.id == value))
      end

    status_match? =
      case status do
        nil -> true
        value -> snapshot.room.status == value
      end

    participant_match? and status_match?
  end

  defp matches_contribution_filters?(
         %Contribution{} = contribution,
         participant_id,
         assignment_id,
         kind
       ) do
    participant_match? = is_nil(participant_id) or contribution.participant_id == participant_id
    assignment_match? = is_nil(assignment_id) or contribution.assignment_id == assignment_id
    kind_match? = is_nil(kind) or contribution.kind == kind
    participant_match? and assignment_match? and kind_match?
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) do
    from(record in query, where: record.status == ^status)
  end

  defp maybe_limit(query, nil), do: query

  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0 do
    from(record in query, limit: ^limit)
  end

  defp maybe_limit(query, _limit), do: query

  defp maybe_take(list, nil), do: list
  defp maybe_take(list, limit) when is_integer(limit) and limit > 0, do: Enum.take(list, limit)
  defp maybe_take(list, _limit), do: list

  defp reduce_room_snapshot(snapshot, acc, participant_id, status) do
    case rehydrate_room_snapshot(snapshot) do
      {:ok, room_snapshot} ->
        next_acc =
          if room_matches?(room_snapshot, participant_id, status),
            do: acc ++ [room_snapshot],
            else: acc

        {:cont, {:ok, next_acc}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

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
