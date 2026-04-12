defmodule JidoHiveServer.Collaboration.ParticipantSessionRegistry do
  @moduledoc false

  use GenServer

  alias JidoHiveServer.Collaboration.Schema.Assignment
  alias Phoenix.PubSub

  @registry_ready_topic "participant_sessions:system"
  @lifecycle_topic "participant_sessions:lifecycle"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register_session(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:register_session, attrs})
  end

  def acknowledge_catch_up(room_id, session_id, through_sequence)
      when is_binary(room_id) and is_binary(session_id) and is_integer(through_sequence) do
    GenServer.call(__MODULE__, {:acknowledge_catch_up, room_id, session_id, through_sequence})
  end

  def unregister_session(room_id, session_id)
      when is_binary(room_id) and is_binary(session_id) do
    GenServer.call(__MODULE__, {:unregister_session, room_id, session_id})
  end

  def availability(room_id) when is_binary(room_id) do
    GenServer.call(__MODULE__, {:availability, room_id})
  end

  def deliver_assignment_offer(room_id, %Assignment{} = assignment) when is_binary(room_id) do
    GenServer.cast(__MODULE__, {:deliver_assignment_offer, room_id, assignment})
  end

  def disconnect_room(room_id) when is_binary(room_id) do
    GenServer.cast(__MODULE__, {:disconnect_room, room_id})
  end

  @impl true
  def init(_opts) do
    broadcast_registry_ready()
    {:ok, %{sessions: %{}, refs: %{}}}
  end

  @impl true
  def handle_call({:register_session, attrs}, _from, state) do
    room_id = Map.fetch!(attrs, :room_id)
    session_id = Map.fetch!(attrs, :session_id)
    pid = Map.fetch!(attrs, :pid)
    mode = Map.fetch!(attrs, :mode)
    participant_id = Map.get(attrs, :participant_id)
    caught_up = Map.get(attrs, :caught_up, false)
    catch_up_target_sequence = Map.get(attrs, :catch_up_target_sequence)
    catch_up_timeout_ms = Map.get(attrs, :catch_up_timeout_ms, 0)

    ref = Process.monitor(pid)
    timeout_ref = maybe_schedule_timeout(room_id, session_id, caught_up, catch_up_timeout_ms)

    session =
      attrs
      |> Map.put(:mode, mode)
      |> Map.put(:participant_id, participant_id)
      |> Map.put(:ref, ref)
      |> Map.put(:timeout_ref, timeout_ref)
      |> Map.put(:catch_up_target_sequence, catch_up_target_sequence)
      |> Map.put(:caught_up, caught_up)

    next_state =
      state
      |> put_session(room_id, session_id, session)
      |> put_ref(ref, room_id, session_id)

    broadcast_lifecycle(:joined, session)
    {:reply, :ok, next_state}
  end

  def handle_call({:acknowledge_catch_up, room_id, session_id, through_sequence}, _from, state) do
    case get_session(state, room_id, session_id) do
      nil ->
        {:reply, {:error, :unknown_session}, state}

      session ->
        target = Map.get(session, :catch_up_target_sequence, 0) || 0

        if through_sequence >= target do
          next_session =
            session
            |> cancel_timeout()
            |> Map.put(:caught_up, true)
            |> Map.put(:last_seen_event_sequence, through_sequence)

          next_state = put_session(state, room_id, session_id, next_session)
          broadcast_lifecycle(:caught_up, next_session)
          {:reply, :ok, next_state}
        else
          send(session.pid, {:participant_session_invalid_ack, room_id, session_id})
          {:reply, {:error, :invalid_ack}, remove_session(state, room_id, session_id)}
        end
    end
  end

  def handle_call({:unregister_session, room_id, session_id}, _from, state) do
    {:reply, :ok, remove_session(state, room_id, session_id)}
  end

  def handle_call({:availability, room_id}, _from, state) do
    availability =
      state
      |> room_sessions(room_id)
      |> Enum.filter(fn {_session_id, session} ->
        session.mode == "participant" and session.caught_up and is_binary(session.participant_id)
      end)
      |> Map.new(fn {_session_id, session} ->
        {session.participant_id,
         %{
           session_id: session.session_id,
           participant_id: session.participant_id,
           participant_meta: Map.get(session, :participant_meta, %{}),
           target_id: get_in(session, [:participant_meta, "target_id"]),
           capability_id: get_in(session, [:participant_meta, "capability_id"])
         }}
      end)

    {:reply, availability, state}
  end

  @impl true
  def handle_cast({:deliver_assignment_offer, room_id, %Assignment{} = assignment}, state) do
    state
    |> room_sessions(room_id)
    |> Enum.each(fn {_session_id, session} ->
      if session.mode == "participant" and session.caught_up and
           session.participant_id == assignment.participant_id do
        send(session.pid, {:assignment_offer, assignment})
      end
    end)

    {:noreply, state}
  end

  def handle_cast({:disconnect_room, room_id}, state) do
    state
    |> room_sessions(room_id)
    |> Enum.each(fn {_session_id, session} ->
      send(session.pid, {:disconnect_room, room_id})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:catch_up_timeout, room_id, session_id}, state) do
    case get_session(state, room_id, session_id) do
      nil ->
        {:noreply, state}

      session ->
        send(session.pid, {:participant_session_timeout, room_id, session_id})
        {:noreply, remove_session(state, room_id, session_id)}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.refs, ref) do
      nil ->
        {:noreply, state}

      {room_id, session_id} ->
        {:noreply, remove_session(state, room_id, session_id)}
    end
  end

  defp room_sessions(state, room_id) do
    Map.get(state.sessions, room_id, %{})
  end

  defp get_session(state, room_id, session_id) do
    state
    |> room_sessions(room_id)
    |> Map.get(session_id)
  end

  defp put_session(state, room_id, session_id, session) do
    update_in(state.sessions, fn sessions ->
      Map.update(sessions, room_id, %{session_id => session}, &Map.put(&1, session_id, session))
    end)
  end

  defp put_ref(state, ref, room_id, session_id) do
    %{state | refs: Map.put(state.refs, ref, {room_id, session_id})}
  end

  defp remove_session(state, room_id, session_id) do
    case get_session(state, room_id, session_id) do
      nil ->
        state

      session ->
        _ = cancel_timeout(session)
        Process.demonitor(session.ref, [:flush])
        broadcast_lifecycle(:left, session)

        sessions =
          update_in(state.sessions, fn sessions ->
            sessions
            |> Map.update(room_id, %{}, &Map.delete(&1, session_id))
            |> drop_empty_rooms()
          end)

        refs = Map.delete(state.refs, session.ref)
        %{state | sessions: sessions, refs: refs}
    end
  end

  defp maybe_schedule_timeout(_room_id, _session_id, true, _timeout_ms), do: nil

  defp maybe_schedule_timeout(room_id, session_id, false, timeout_ms)
       when is_integer(timeout_ms) and timeout_ms > 0 do
    Process.send_after(self(), {:catch_up_timeout, room_id, session_id}, timeout_ms)
  end

  defp maybe_schedule_timeout(_room_id, _session_id, _caught_up, _timeout_ms), do: nil

  defp cancel_timeout(%{timeout_ref: nil} = session), do: session

  defp cancel_timeout(%{timeout_ref: timeout_ref} = session) do
    _ = Process.cancel_timer(timeout_ref)
    %{session | timeout_ref: nil}
  end

  defp drop_empty_rooms(sessions) do
    sessions
    |> Enum.reject(fn {_key, value} -> value == %{} end)
    |> Map.new()
  end

  defp broadcast_registry_ready do
    PubSub.broadcast(JidoHiveServer.PubSub, @registry_ready_topic, :registry_ready)
  end

  defp broadcast_lifecycle(kind, session) do
    PubSub.broadcast(
      JidoHiveServer.PubSub,
      @lifecycle_topic,
      {:participant_session, kind, session}
    )
  end
end
