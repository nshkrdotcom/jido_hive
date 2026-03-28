defmodule JidoHiveServer.RemoteExec do
  @moduledoc false

  use GenServer

  require Logger

  alias JidoHiveServer.Persistence

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register_connection(channel_pid, payload) when is_pid(channel_pid) and is_map(payload) do
    GenServer.call(__MODULE__, {:register_connection, channel_pid, payload})
  end

  def upsert_target(channel_pid, payload) when is_pid(channel_pid) and is_map(payload) do
    GenServer.call(__MODULE__, {:upsert_target, channel_pid, payload})
  end

  def dispatch_job(target_id, job) when is_binary(target_id) and is_map(job) do
    GenServer.call(__MODULE__, {:dispatch_job, target_id, job})
  end

  def remove_channel(channel_pid) when is_pid(channel_pid) do
    GenServer.call(__MODULE__, {:remove_channel, channel_pid})
  end

  def fetch_target(target_id) when is_binary(target_id) do
    GenServer.call(__MODULE__, {:fetch_target, target_id})
  end

  def list_targets do
    GenServer.call(__MODULE__, :list_targets)
  end

  @impl true
  def init(_opts) do
    :ok = Persistence.mark_all_targets_offline()
    {:ok, %{connections: %{}, targets: %{}}}
  end

  @impl true
  def handle_call({:register_connection, channel_pid, payload}, _from, state) do
    connection = %{
      connection_id: unique_id("conn"),
      channel_pid: channel_pid,
      workspace_id: payload["workspace_id"],
      user_id: payload["user_id"],
      participant_id: payload["participant_id"],
      participant_role: payload["participant_role"]
    }

    connections = Map.put(state.connections, channel_pid, connection)
    {:reply, {:ok, connection}, %{state | connections: connections}}
  end

  def handle_call({:upsert_target, channel_pid, payload}, _from, state) do
    connection = Map.fetch!(state.connections, channel_pid)

    target =
      %{
        target_id: payload["target_id"],
        capability_id: payload["capability_id"],
        channel_pid: channel_pid,
        workspace_id: payload["workspace_id"] || connection.workspace_id,
        user_id: payload["user_id"] || connection.user_id,
        participant_id: payload["participant_id"] || connection.participant_id,
        participant_role: payload["participant_role"] || connection.participant_role,
        runtime_driver: payload["runtime_driver"] || "asm",
        provider: payload["provider"] || "codex",
        workspace_root: payload["workspace_root"] || File.cwd!()
      }

    targets = Map.put(state.targets, target.target_id, target)

    Logger.info(
      "target online target=#{target.target_id} role=#{target.participant_role} " <>
        "provider=#{target.provider} runtime=#{target.runtime_driver}"
    )

    {:ok, _snapshot} = Persistence.upsert_target(target)
    :ok = JidoHiveServer.IntegrationsBootstrap.sync_target_projection!(Map.values(targets))
    {:reply, {:ok, target}, %{state | targets: targets}}
  end

  def handle_call({:dispatch_job, target_id, job}, _from, state) do
    case Map.fetch(state.targets, target_id) do
      {:ok, target} ->
        send(target.channel_pid, {:dispatch_job, job})
        {:reply, :ok, state}

      :error ->
        {:reply, {:error, :unknown_target}, state}
    end
  end

  def handle_call({:fetch_target, target_id}, _from, state) do
    case Map.fetch(state.targets, target_id) do
      {:ok, target} -> {:reply, {:ok, target}, state}
      :error -> {:reply, Persistence.fetch_target(target_id), state}
    end
  end

  def handle_call(:list_targets, _from, state) do
    {:reply, Persistence.list_targets(status: "online"), state}
  end

  def handle_call({:remove_channel, channel_pid}, _from, state) do
    connections = Map.delete(state.connections, channel_pid)

    targets =
      state.targets
      |> Enum.reject(fn {_target_id, target} -> target.channel_pid == channel_pid end)
      |> Map.new()

    Enum.each(state.targets, fn {_target_id, target} ->
      if target.channel_pid == channel_pid do
        Logger.info("target offline target=#{target.target_id} role=#{target.participant_role}")
        :ok = Persistence.mark_target_offline(target.target_id)
      end
    end)

    :ok = JidoHiveServer.IntegrationsBootstrap.sync_target_projection!(Map.values(targets))
    {:reply, :ok, %{state | connections: connections, targets: targets}}
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
