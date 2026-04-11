defmodule JidoHiveClient.SessionState do
  @moduledoc false

  defstruct session_id: nil,
            connection_status: :starting,
            identity: %{},
            metadata: %{},
            metrics: %{
              events_recorded: 0,
              reconnect_count: 0
            },
            last_error: nil,
            updated_at: nil

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    identity = identity_from_opts(opts)
    room_id = Keyword.fetch!(opts, :room_id)
    session_id = "#{identity.workspace_id}:#{room_id}:#{identity.participant_id}"

    %__MODULE__{
      session_id: session_id,
      identity: identity,
      metadata: %{mode: "embedded", room_id: room_id},
      updated_at: DateTime.utc_now()
    }
  end

  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = state) do
    %{
      session_id: state.session_id,
      connection_status: state.connection_status,
      identity: state.identity,
      metadata: state.metadata,
      metrics: state.metrics,
      last_error: state.last_error,
      updated_at: state.updated_at
    }
  end

  @spec connection_changed(t(), atom(), map()) :: t()
  def connection_changed(%__MODULE__{} = state, status, payload \\ %{})
      when is_atom(status) and is_map(payload) do
    reconnect_count =
      if state.connection_status == :stopped and status == :ready do
        state.metrics.reconnect_count + 1
      else
        state.metrics.reconnect_count
      end

    state
    |> put_in([Access.key(:metrics), Access.key(:reconnect_count)], reconnect_count)
    |> Map.put(:connection_status, status)
    |> Map.put(:metadata, Map.merge(state.metadata, atomize_keys(payload)))
    |> maybe_clear_error(status)
    |> touch()
  end

  @spec record_event(t(), map()) :: t()
  def record_event(%__MODULE__{} = state, _event) do
    state
    |> update_in([Access.key(:metrics), Access.key(:events_recorded)], &(&1 + 1))
    |> touch()
  end

  @spec put_error(t(), term()) :: t()
  def put_error(%__MODULE__{} = state, reason) do
    state
    |> Map.put(:last_error, reason)
    |> touch()
  end

  @spec clear_error(t()) :: t()
  def clear_error(%__MODULE__{} = state) do
    state
    |> Map.put(:last_error, nil)
    |> touch()
  end

  defp maybe_clear_error(state, :ready), do: Map.put(state, :last_error, nil)
  defp maybe_clear_error(state, _status), do: state

  defp touch(%__MODULE__{} = state), do: %{state | updated_at: DateTime.utc_now()}

  defp identity_from_opts(opts) do
    %{
      workspace_id: Keyword.get(opts, :workspace_id, "workspace-local"),
      user_id: Keyword.get(opts, :user_id, "user-local"),
      participant_id: Keyword.get(opts, :participant_id, "participant-local"),
      participant_role: Keyword.get(opts, :participant_role, "operator"),
      participant_kind: Keyword.get(opts, :participant_kind, "human"),
      target_id: Keyword.get(opts, :target_id, "embedded-session"),
      capability_id: Keyword.get(opts, :capability_id, "human.chat"),
      workspace_root: Keyword.get(opts, :workspace_root, File.cwd!())
    }
  end

  defp atomize_keys(map) do
    Enum.into(map, %{}, fn
      {"mode", value} -> {:mode, value}
      {"room_id", value} -> {:room_id, value}
      {key, value} when is_binary(key) -> {key, value}
      {key, value} -> {key, value}
    end)
  end
end
