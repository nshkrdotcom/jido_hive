defmodule JidoHiveServerWeb.RelayChannel do
  use Phoenix.Channel

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
    {:ok, _snapshot} = Collaboration.receive_result(payload)
    {:reply, {:ok, %{"accepted" => true}}, socket}
  end

  @impl true
  def handle_info({:dispatch_job, job}, socket) do
    push(socket, "job.start", job)
    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, _socket) do
    RemoteExec.remove_channel(self())
    :ok
  end
end
