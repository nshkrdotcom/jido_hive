defmodule JidoHiveServer.Collaboration.RoomServer do
  @moduledoc false

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoHiveServer.Collaboration.{EventReducer, ExecutionPlan, RoomAgent}
  alias JidoHiveServer.Collaboration.Schema.RoomEvent
  alias JidoHiveServer.Collaboration.Workflow.Registry, as: WorkflowRegistry
  alias JidoHiveServer.Collaboration.Workflows.DefaultRoundRobin
  alias JidoHiveServer.Persistence

  def start_link(opts) when is_list(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, opts, name: via(room_id))
  end

  def open_turn(server, payload) when is_map(payload) do
    GenServer.call(server, {:open_turn, payload})
  end

  def apply_result(server, payload) when is_map(payload) do
    GenServer.call(server, {:apply_result, payload})
  end

  def abandon_turn(server, payload) when is_map(payload) do
    GenServer.call(server, {:abandon_turn, payload})
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
    initial_state =
      Keyword.get_lazy(opts, :snapshot, fn ->
        %{
          room_id: Keyword.fetch!(opts, :room_id),
          session_id: Keyword.fetch!(opts, :session_id),
          brief: Keyword.fetch!(opts, :brief),
          rules: Keyword.get(opts, :rules, []),
          participants: Keyword.get(opts, :participants, []),
          turns: [],
          context_entries: [],
          disputes: [],
          current_turn: %{},
          execution_plan:
            Keyword.get_lazy(opts, :execution_plan, fn ->
              workflow_id = Keyword.get(opts, :workflow_id, DefaultRoundRobin.id())
              workflow_config = Keyword.get(opts, :workflow_config, %{})
              stages = workflow_stages(workflow_id, workflow_config)

              case ExecutionPlan.new(Keyword.get(opts, :participants, []), stages: stages) do
                {:ok, plan} -> plan
                {:error, _} -> %{}
              end
            end),
          workflow_id: Keyword.get(opts, :workflow_id, DefaultRoundRobin.id()),
          workflow_config: Keyword.get(opts, :workflow_config, %{}),
          workflow_state: Keyword.get(opts, :workflow_state, %{applied_event_ids: []}),
          status: "idle",
          phase: "idle",
          round: 0,
          next_entry_seq: 1,
          next_dispute_seq: 1
        }
      end)

    {:ok, %{agent: RoomAgent.new(state: initial_state)}}
  end

  @impl true
  def handle_call({:open_turn, payload}, _from, %{agent: agent} = state) do
    with {:ok, event} <- room_event(agent.state.room_id, :turn_opened, payload),
         {:ok, agent} <- apply_event(agent, event),
         :ok <- Persistence.append_room_events(agent.state.room_id, [event]),
         {:ok, _snapshot} <- Persistence.persist_room_snapshot(agent.state) do
      publish_signal("room.turn.opened", agent.state)
      {:reply, {:ok, agent.state}, %{state | agent: agent}}
    end
  end

  def handle_call({:apply_result, payload}, _from, %{agent: agent} = state) do
    event_type =
      case Map.get(payload, "status") || Map.get(payload, :status) do
        "failed" -> :turn_failed
        _other -> :turn_completed
      end

    with {:ok, event} <- room_event(agent.state.room_id, event_type, payload),
         {:ok, agent} <- apply_event(agent, event),
         :ok <- Persistence.append_room_events(agent.state.room_id, [event]),
         {:ok, _snapshot} <- Persistence.persist_room_snapshot(agent.state) do
      publish_signal("room.turn.completed", agent.state)
      {:reply, {:ok, agent.state}, %{state | agent: agent}}
    end
  end

  def handle_call({:abandon_turn, payload}, _from, %{agent: agent} = state) do
    with {:ok, event} <- room_event(agent.state.room_id, :turn_abandoned, payload),
         {:ok, agent} <- apply_event(agent, event),
         :ok <- Persistence.append_room_events(agent.state.room_id, [event]),
         {:ok, _snapshot} <- Persistence.persist_room_snapshot(agent.state) do
      publish_signal("room.turn.abandoned", agent.state)
      {:reply, {:ok, agent.state}, %{state | agent: agent}}
    end
  end

  def handle_call({:set_runtime_state, payload}, _from, %{agent: agent} = state) do
    with {:ok, event} <- room_event(agent.state.room_id, :runtime_state_changed, payload),
         {:ok, agent} <- apply_event(agent, event),
         :ok <- Persistence.append_room_events(agent.state.room_id, [event]),
         {:ok, _snapshot} <- Persistence.persist_room_snapshot(agent.state) do
      publish_signal("room.runtime.updated", agent.state)
      {:reply, {:ok, agent.state}, %{state | agent: agent}}
    end
  end

  def handle_call(:snapshot, _from, %{agent: agent} = state) do
    {:reply, {:ok, agent.state}, state}
  end

  defp normalize_payload(payload) do
    payload
    |> Enum.into(%{}, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_binary(key), do: String.to_atom(key)
  defp normalize_key(key), do: key

  defp publish_signal(type, data) do
    signal = Signal.new!(type, data, source: "/jido_hive_server/room_server")
    _ = Bus.publish(JidoHiveServer.SignalBus, [signal])
    :ok
  end

  defp apply_event(agent, %RoomEvent{} = event) do
    {:ok, %{agent | state: EventReducer.apply_event(agent.state, event)}}
  end

  defp room_event(room_id, type, payload)
       when is_binary(room_id) and is_atom(type) and is_map(payload) do
    RoomEvent.new(%{
      event_id: unique_id("evt"),
      room_id: room_id,
      type: type,
      payload: normalize_payload(payload),
      recorded_at: DateTime.utc_now()
    })
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp workflow_stages(workflow_id, workflow_config) do
    case WorkflowRegistry.fetch_module(workflow_id) do
      {:ok, module} -> module.stages(workflow_config)
      {:error, _reason} -> DefaultRoundRobin.stages(%{})
    end
  end
end
