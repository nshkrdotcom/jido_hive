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
  def handle_in(event, payload, socket) when event in ["relay.hello", "relay.hello.v2"] do
    with {:ok, {:relay_hello, connection_payload}} <-
           ProtocolCodec.decode_inbound(event, payload, socket.assigns.workspace_id),
         {:ok, connection} <- RemoteExec.register_connection(self(), connection_payload) do
      {:reply, {:ok, %{"connection_id" => connection.connection_id}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, error_payload(reason)}, socket}
    end
  end

  def handle_in(event, payload, socket) when event in ["target.upsert", "target.register"] do
    with {:ok, {:target_register, target_payload}} <-
           ProtocolCodec.decode_inbound(event, payload, socket.assigns.workspace_id),
         {:ok, target} <- RemoteExec.upsert_target(self(), target_payload) do
      {:reply, {:ok, %{"target_id" => target.target_id}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, error_payload(reason)}, socket}
    end
  end

  def handle_in(event, payload, socket) when event in ["job.result", "job.result.v2"] do
    case ProtocolCodec.decode_inbound(event, payload, socket.assigns.workspace_id) do
      {:ok, {:job_result, result_payload}} ->
        Logger.info(
          "job result room=#{result_payload["room_id"]} participant=#{result_payload["participant_id"]} " <>
            "status=#{result_payload["status"]} actions=#{action_summary(result_payload["actions"])}"
        )

        {:ok, _snapshot} = Collaboration.receive_result(result_payload)
        {:reply, {:ok, %{"accepted" => true}}, socket}

      {:error, reason} ->
        {:reply, {:error, error_payload(reason)}, socket}
    end
  end

  @impl true
  def handle_info({:dispatch_job, job}, socket) do
    Logger.info(
      "dispatch room=#{job["room_id"]} phase=#{get_in(job, ["collaboration_envelope", "turn", "phase"])} " <>
        "participant=#{job["participant_id"]} target=#{job["target_id"]}"
    )

    push(socket, "job.start", ProtocolCodec.encode_job_start(job))
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

  defp error_payload({:missing_field, field}), do: %{"error" => "missing_field", "field" => field}
  defp error_payload({:invalid_field, field}), do: %{"error" => "invalid_field", "field" => field}
  defp error_payload(reason), do: %{"error" => inspect(reason)}
end
