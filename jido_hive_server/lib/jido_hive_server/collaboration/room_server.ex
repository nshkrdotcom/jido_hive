defmodule JidoHiveServer.Collaboration.RoomServer do
  @moduledoc false

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoHiveServer.Collaboration.EventReducer
  alias JidoHiveServer.Collaboration.Schema.RoomEvent
  alias JidoHiveServer.Persistence

  def start_link(opts) when is_list(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, opts, name: via(room_id))
  end

  def open_assignment(server, payload) when is_map(payload) do
    GenServer.call(server, {:open_assignment, payload})
  end

  def record_contribution(server, payload) when is_map(payload) do
    GenServer.call(server, {:record_contribution, payload})
  end

  def abandon_assignment(server, payload) when is_map(payload) do
    GenServer.call(server, {:abandon_assignment, payload})
  end

  def set_runtime_state(server, payload) when is_map(payload) do
    GenServer.call(server, {:set_runtime_state, payload})
  end

  def snapshot(server) do
    GenServer.call(server, :snapshot)
  end

  def via(room_id) do
    {:via, Registry, {JidoHiveServer.Collaboration.Registry, room_id}}
  end

  @impl true
  def init(opts) do
    initial_snapshot = Keyword.fetch!(opts, :snapshot)
    {:ok, %{snapshot: initial_snapshot}}
  end

  @impl true
  def handle_call({:open_assignment, payload}, _from, %{snapshot: snapshot} = state) do
    with {:ok, event} <- room_event(snapshot.room_id, :assignment_opened, payload),
         next_snapshot <- EventReducer.apply_event(snapshot, event),
         :ok <- Persistence.append_room_events(snapshot.room_id, [event]),
         {:ok, _snapshot} <- Persistence.persist_room_snapshot(next_snapshot) do
      publish_signal("room.assignment.opened", next_snapshot)
      {:reply, {:ok, next_snapshot}, %{state | snapshot: next_snapshot}}
    end
  end

  def handle_call({:record_contribution, payload}, _from, %{snapshot: snapshot} = state) do
    with {:ok, event} <- room_event(snapshot.room_id, :contribution_recorded, payload),
         next_snapshot <- EventReducer.apply_event(snapshot, event),
         :ok <- Persistence.append_room_events(snapshot.room_id, [event]),
         {:ok, _snapshot} <- Persistence.persist_room_snapshot(next_snapshot) do
      publish_signal("room.contribution.recorded", next_snapshot)
      {:reply, {:ok, next_snapshot}, %{state | snapshot: next_snapshot}}
    end
  end

  def handle_call({:abandon_assignment, payload}, _from, %{snapshot: snapshot} = state) do
    with {:ok, event} <- room_event(snapshot.room_id, :assignment_abandoned, payload),
         next_snapshot <- EventReducer.apply_event(snapshot, event),
         :ok <- Persistence.append_room_events(snapshot.room_id, [event]),
         {:ok, _snapshot} <- Persistence.persist_room_snapshot(next_snapshot) do
      publish_signal("room.assignment.abandoned", next_snapshot)
      {:reply, {:ok, next_snapshot}, %{state | snapshot: next_snapshot}}
    end
  end

  def handle_call({:set_runtime_state, payload}, _from, %{snapshot: snapshot} = state) do
    with {:ok, event} <- room_event(snapshot.room_id, :runtime_state_changed, payload),
         next_snapshot <- EventReducer.apply_event(snapshot, event),
         :ok <- Persistence.append_room_events(snapshot.room_id, [event]),
         {:ok, _snapshot} <- Persistence.persist_room_snapshot(next_snapshot) do
      publish_signal("room.runtime.updated", next_snapshot)
      {:reply, {:ok, next_snapshot}, %{state | snapshot: next_snapshot}}
    end
  end

  def handle_call(:snapshot, _from, %{snapshot: snapshot} = state) do
    {:reply, {:ok, snapshot}, state}
  end

  defp room_event(room_id, type, payload)
       when is_binary(room_id) and is_atom(type) and is_map(payload) do
    RoomEvent.new(%{
      event_id: unique_id("evt"),
      room_id: room_id,
      type: type,
      payload: payload,
      recorded_at: DateTime.utc_now()
    })
  end

  defp publish_signal(type, data) do
    signal = Signal.new!(type, data, source: "/jido_hive_server/room_server")
    _ = Bus.publish(JidoHiveServer.SignalBus, [signal])
    :ok
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
