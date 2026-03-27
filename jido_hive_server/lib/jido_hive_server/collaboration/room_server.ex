defmodule JidoHiveServer.Collaboration.RoomServer do
  @moduledoc false

  use GenServer

  alias JidoHiveServer.Collaboration.Actions.{ApplyResult, OpenTurn}
  alias JidoHiveServer.Collaboration.RoomAgent

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

  def snapshot(server) do
    GenServer.call(server, :snapshot)
  end

  def via(room_id) do
    {:via, Registry, {JidoHiveServer.Collaboration.Registry, room_id}}
  end

  @impl true
  def init(opts) do
    initial_state = %{
      room_id: Keyword.fetch!(opts, :room_id),
      session_id: Keyword.fetch!(opts, :session_id),
      brief: Keyword.fetch!(opts, :brief),
      rules: Keyword.get(opts, :rules, []),
      participants: Keyword.get(opts, :participants, []),
      turns: [],
      context_entries: [],
      disputes: [],
      current_turn: %{},
      status: "idle",
      round: 0,
      next_entry_seq: 1,
      next_dispute_seq: 1
    }

    {:ok, %{agent: RoomAgent.new(state: initial_state)}}
  end

  @impl true
  def handle_call({:open_turn, payload}, _from, %{agent: agent} = state) do
    {:ok, _result, state_op} = OpenTurn.run(normalize_payload(payload), %{state: agent.state})
    {:ok, agent} = apply_state_op(agent, state_op)
    publish_signal("room.turn.opened", agent.state)
    {:reply, {:ok, agent.state}, %{state | agent: agent}}
  end

  def handle_call({:apply_result, payload}, _from, %{agent: agent} = state) do
    {:ok, _result, state_op} = ApplyResult.run(normalize_payload(payload), %{state: agent.state})
    {:ok, agent} = apply_state_op(agent, state_op)
    publish_signal("room.turn.completed", agent.state)
    {:reply, {:ok, agent.state}, %{state | agent: agent}}
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
    signal = Jido.Signal.new!(type, data, source: "/jido_hive_server/room_server")
    _ = Jido.Signal.Bus.publish(JidoHiveServer.SignalBus, [signal])
    :ok
  end

  defp apply_state_op(agent, %Jido.Agent.StateOp.SetState{attrs: attrs}) do
    RoomAgent.set(agent, attrs)
  end

  defp apply_state_op(agent, %Jido.Agent.StateOp.ReplaceState{state: new_state}) do
    {:ok, %{agent | state: new_state}}
  end
end
