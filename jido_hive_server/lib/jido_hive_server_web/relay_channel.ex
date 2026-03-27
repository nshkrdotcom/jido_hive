defmodule JidoHiveServerWeb.RelayChannel do
  @moduledoc false

  use Phoenix.Channel

  require Logger

  alias JidoHiveServer.{Collaboration, RemoteExec}

  @impl true
  def join("relay:" <> workspace_id, _params, socket) do
    {:ok, %{joined: true}, assign(socket, :workspace_id, workspace_id)}
  end

  @impl true
  def handle_in("relay.hello", payload, socket) do
    {:ok, connection} =
      RemoteExec.register_connection(
        self(),
        Map.put(payload, "workspace_id", socket.assigns.workspace_id)
      )

    {:reply, {:ok, %{"connection_id" => connection.connection_id}}, socket}
  end

  def handle_in("target.upsert", payload, socket) do
    {:ok, target} =
      RemoteExec.upsert_target(
        self(),
        Map.put(payload, "workspace_id", socket.assigns.workspace_id)
      )

    {:reply, {:ok, %{"target_id" => target.target_id}}, socket}
  end

  def handle_in("job.result", payload, socket) do
    Logger.info(
      "job result room=#{payload["room_id"]} participant=#{payload["participant_id"]} " <>
        "status=#{payload["status"]} actions=#{action_summary(payload["actions"])}"
    )

    {:ok, _snapshot} = Collaboration.receive_result(payload)
    {:reply, {:ok, %{"accepted" => true}}, socket}
  end

  @impl true
  def handle_info({:dispatch_job, job}, socket) do
    Logger.info(
      "dispatch room=#{job["room_id"]} phase=#{get_in(job, ["collaboration_envelope", "turn", "phase"])} " <>
        "participant=#{job["participant_id"]} target=#{job["target_id"]}"
    )

    push(socket, "job.start", job)
    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, _socket) do
    RemoteExec.remove_channel(self())
    :ok
  end

  defp action_summary(actions) when is_list(actions) do
    actions
    |> Enum.map(&(Map.get(&1, "op") || Map.get(&1, :op) || "unknown"))
    |> Enum.uniq()
    |> case do
      [] -> "none"
      ops -> Enum.join(ops, ",")
    end
  end

  defp action_summary(_other), do: "none"
end
