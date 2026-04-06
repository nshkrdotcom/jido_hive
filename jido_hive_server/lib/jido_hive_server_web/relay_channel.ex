defmodule JidoHiveServerWeb.RelayChannel do
  @moduledoc false

  use Phoenix.Channel

  require Logger

  alias JidoHiveServer.{Collaboration, RemoteExec}
  alias JidoHiveServer.Collaboration.ProtocolCodec

  @impl true
  def join("relay:" <> workspace_id, _params, socket) do
    {:ok, %{joined: true}, assign(socket, :workspace_id, workspace_id)}
  end

  @impl true
  def handle_in("relay.hello", payload, socket) do
    with {:ok, {:relay_hello, connection_payload}} <-
           ProtocolCodec.decode_inbound("relay.hello", payload, socket.assigns.workspace_id),
         {:ok, connection} <- RemoteExec.register_connection(self(), connection_payload) do
      {:reply, {:ok, %{"connection_id" => connection.connection_id}}, socket}
    else
      {:error, reason} -> {:reply, {:error, error_payload(reason)}, socket}
    end
  end

  def handle_in("participant.upsert", payload, socket) do
    with {:ok, {:participant_upsert, participant_payload}} <-
           ProtocolCodec.decode_inbound(
             "participant.upsert",
             payload,
             socket.assigns.workspace_id
           ),
         {:ok, target} <- RemoteExec.upsert_target(self(), participant_payload) do
      {:reply, {:ok, %{"target_id" => target.target_id}}, socket}
    else
      {:error, reason} -> {:reply, {:error, error_payload(reason)}, socket}
    end
  end

  def handle_in("contribution.submit", payload, socket) do
    case ProtocolCodec.decode_inbound("contribution.submit", payload, socket.assigns.workspace_id) do
      {:ok, {:contribution_submit, contribution_payload}} ->
        Logger.info(
          "contribution room=#{contribution_payload["room_id"]} participant=#{contribution_payload["participant_id"]} type=#{contribution_payload["contribution_type"]} status=#{contribution_payload["status"]}"
        )

        {:ok, _snapshot} = Collaboration.receive_contribution(contribution_payload)
        {:reply, {:ok, %{"accepted" => true}}, socket}

      {:error, reason} ->
        {:reply, {:error, error_payload(reason)}, socket}
    end
  end

  @impl true
  def handle_info({:dispatch_assignment, assignment}, socket) do
    Logger.info(
      "dispatch room=#{assignment["room_id"] || assignment[:room_id]} phase=#{assignment["phase"] || assignment[:phase]} participant=#{assignment["participant_id"] || assignment[:participant_id]} target=#{assignment["target_id"] || assignment[:target_id]}"
    )

    push(socket, "assignment.start", ProtocolCodec.encode_assignment_start(assignment))
    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, _socket) do
    RemoteExec.remove_channel(self())
    :ok
  end

  defp error_payload({:missing_field, field}), do: %{"error" => "missing_field", "field" => field}
  defp error_payload({:invalid_field, field}), do: %{"error" => "invalid_field", "field" => field}
  defp error_payload(reason), do: %{"error" => inspect(reason)}
end
