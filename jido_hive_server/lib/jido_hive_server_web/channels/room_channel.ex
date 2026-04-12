defmodule JidoHiveServerWeb.RoomChannel do
  @moduledoc false

  use Phoenix.Channel

  alias JidoHiveServer.Collaboration
  alias JidoHiveServer.Collaboration.ParticipantSessionRegistry
  alias JidoHiveServer.Collaboration.Schema.Assignment
  alias JidoHiveServerWeb.API
  alias Phoenix.PubSub

  @catch_up_timeout_ms 15_000
  @registry_ready_topic "participant_sessions:system"

  @impl true
  def join("room:" <> room_id, params, socket) do
    with {:ok, snapshot} <- Collaboration.fetch_room_snapshot(room_id),
         {:ok, join_data} <- join_data(room_id, params, snapshot),
         :ok <- maybe_upsert_participant(join_data),
         :ok <- PubSub.subscribe(JidoHiveServer.PubSub, @registry_ready_topic),
         :ok <- ParticipantSessionRegistry.register_session(join_data.registry_attrs) do
      {:ok,
       %{
         current_event_sequence: join_data.current_event_sequence,
         catch_up_required: join_data.catch_up_required,
         catch_up_target_sequence: join_data.catch_up_target_sequence,
         catch_up_timeout_ms: @catch_up_timeout_ms
       }, assign_join(socket, join_data)}
    else
      {:error, reason} ->
        {:error, API.error("invalid_join", inspect(reason))}
    end
  end

  @impl true
  def handle_in("session.caught_up", %{"through_sequence" => through_sequence}, socket)
      when is_integer(through_sequence) do
    case ParticipantSessionRegistry.acknowledge_catch_up(
           socket.assigns.room_id,
           socket.assigns.session_id,
           through_sequence
         ) do
      :ok ->
        {:reply, {:ok, API.data(%{"caught_up" => true})}, assign(socket, :caught_up, true)}

      {:error, reason} ->
        {:reply, {:error, API.error("invalid_catch_up", inspect(reason))}, socket}
    end
  end

  def handle_in("contribution.submit", %{"data" => attrs}, socket) do
    if socket.assigns.mode == "observer" do
      {:reply, {:error, API.error("forbidden", "Observer sessions cannot submit contributions")},
       socket}
    else
      participant_id = Map.get(attrs, "participant_id", socket.assigns.participant_id)
      submit_contribution_reply(socket, attrs, participant_id)
    end
  end

  def handle_in(
        "assignment.update",
        %{"data" => %{"assignment_id" => assignment_id, "status" => status}},
        socket
      ) do
    if socket.assigns.mode == "observer" do
      {:reply, {:error, API.error("forbidden", "Observer sessions cannot update assignments")},
       socket}
    else
      with {:ok, assignments} <-
             Collaboration.list_assignments(socket.assigns.room_id,
               participant_id: socket.assigns.participant_id
             ),
           true <-
             Enum.any?(assignments, &(&1.id == assignment_id)) or {:error, :assignment_not_found},
           {:ok, _snapshot} <-
             Collaboration.update_assignment(socket.assigns.room_id, assignment_id, status) do
        {:reply, {:ok, API.data(%{"accepted" => true})}, socket}
      else
        {:error, :assignment_not_found} ->
          {:reply, {:error, API.error("assignment_not_found", "Assignment not found")}, socket}

        {:error, reason} ->
          {:reply, {:error, API.error("invalid_assignment_patch", inspect(reason))}, socket}
      end
    end
  end

  def handle_in("room.patch", %{"data" => attrs}, socket) do
    if socket.assigns.mode == "observer" do
      {:reply, {:error, API.error("forbidden", "Observer sessions cannot patch rooms")}, socket}
    else
      case Collaboration.patch_room(socket.assigns.room_id, attrs) do
        {:ok, _snapshot} ->
          {:reply, {:ok, API.data(%{"accepted" => true})}, socket}

        {:error, reason} ->
          {:reply, {:error, API.error("invalid_room_patch", inspect(reason))}, socket}
      end
    end
  end

  def handle_in("participant.leave", %{"data" => _attrs}, socket) do
    if socket.assigns.mode == "observer" do
      {:reply, {:error, API.error("forbidden", "Observer sessions leave by disconnecting")},
       socket}
    else
      _ = Collaboration.remove_participant(socket.assigns.room_id, socket.assigns.participant_id)

      _ =
        ParticipantSessionRegistry.unregister_session(
          socket.assigns.room_id,
          socket.assigns.session_id
        )

      send(self(), {:disconnect_room, socket.assigns.room_id})
      {:reply, {:ok, API.data(%{"accepted" => true})}, socket}
    end
  end

  def handle_in(_event, _payload, socket) do
    {:reply, {:error, API.error("unsupported_event", "Unsupported channel event")}, socket}
  end

  @impl true
  def handle_info({:assignment_offer, %Assignment{} = assignment}, socket) do
    push(socket, "assignment.offer", API.data(assignment))
    {:noreply, socket}
  end

  def handle_info(:registry_ready, socket) do
    _ = ParticipantSessionRegistry.register_session(socket.assigns.registry_attrs)
    {:noreply, socket}
  end

  def handle_info({:participant_session_timeout, room_id, session_id}, socket)
      when room_id == socket.assigns.room_id and session_id == socket.assigns.session_id do
    {:stop, :normal, socket}
  end

  def handle_info({:participant_session_invalid_ack, room_id, session_id}, socket)
      when room_id == socket.assigns.room_id and session_id == socket.assigns.session_id do
    {:stop, :normal, socket}
  end

  def handle_info({:disconnect_room, room_id}, socket) when room_id == socket.assigns.room_id do
    {:stop, :normal, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    _ =
      ParticipantSessionRegistry.unregister_session(
        socket.assigns.room_id,
        socket.assigns.session_id
      )

    :ok
  end

  defp submit_contribution_reply(socket, _attrs, participant_id)
       when participant_id != socket.assigns.participant_id do
    {:reply, {:error, API.error("forbidden", "Participant id mismatch")}, socket}
  end

  defp submit_contribution_reply(socket, attrs, _participant_id) do
    case Collaboration.submit_contribution(
           socket.assigns.room_id,
           attrs
           |> Map.put("participant_id", socket.assigns.participant_id)
           |> Map.put_new("meta", %{})
         ) do
      {:ok, _snapshot} ->
        {:reply, {:ok, API.data(%{"accepted" => true})}, socket}

      {:error, reason} ->
        {:reply, {:error, API.error("invalid_contribution", inspect(reason))}, socket}
    end
  end

  defp join_data(room_id, params, snapshot) do
    session = Map.get(params, "session", %{})
    mode = Map.get(session, "mode")
    last_seen_event_sequence = Map.get(session, "last_seen_event_sequence")

    current_event_sequence = max(snapshot.clocks.next_event_sequence - 1, 0)
    catch_up_required = catch_up_required?(last_seen_event_sequence, current_event_sequence)
    catch_up_target_sequence = if(catch_up_required, do: current_event_sequence, else: 0)
    session_id = new_session_id(room_id)

    case mode do
      "observer" ->
        {:ok,
         %{
           mode: "observer",
           current_event_sequence: current_event_sequence,
           catch_up_required: catch_up_required,
           catch_up_target_sequence: catch_up_target_sequence,
           registry_attrs: %{
             room_id: room_id,
             session_id: session_id,
             pid: self(),
             mode: "observer",
             caught_up: not catch_up_required,
             catch_up_target_sequence: catch_up_target_sequence,
             catch_up_timeout_ms: @catch_up_timeout_ms,
             last_seen_event_sequence: last_seen_event_sequence
           }
         }}

      "participant" ->
        participant = Map.get(params, "participant")

        with %{} = participant <- participant,
             id when is_binary(id) <- Map.get(participant, "id"),
             kind when is_binary(kind) <- Map.get(participant, "kind"),
             handle when is_binary(handle) <- Map.get(participant, "handle") do
          participant_meta = Map.get(participant, "meta", %{})

          {:ok,
           %{
             mode: "participant",
             participant: %{
               "id" => id,
               "room_id" => room_id,
               "kind" => kind,
               "handle" => handle,
               "meta" => participant_meta
             },
             participant_id: id,
             current_event_sequence: current_event_sequence,
             catch_up_required: catch_up_required,
             catch_up_target_sequence: catch_up_target_sequence,
             registry_attrs: %{
               room_id: room_id,
               session_id: session_id,
               pid: self(),
               mode: "participant",
               participant_id: id,
               participant_meta: participant_meta,
               caught_up: not catch_up_required,
               catch_up_target_sequence: catch_up_target_sequence,
               catch_up_timeout_ms: @catch_up_timeout_ms,
               last_seen_event_sequence: last_seen_event_sequence
             }
           }}
        else
          _other -> {:error, :invalid_participant_join}
        end

      _other ->
        {:error, :invalid_session_mode}
    end
  end

  defp maybe_upsert_participant(%{mode: "observer"}), do: :ok

  defp maybe_upsert_participant(%{mode: "participant", participant: participant}) do
    case Collaboration.upsert_participant(participant["room_id"], participant) do
      {:ok, _snapshot} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp assign_join(socket, join_data) do
    socket
    |> assign(:room_id, join_data.registry_attrs.room_id)
    |> assign(:session_id, join_data.registry_attrs.session_id)
    |> assign(:mode, join_data.mode)
    |> assign(:participant_id, Map.get(join_data, :participant_id))
    |> assign(:caught_up, not join_data.catch_up_required)
    |> assign(:registry_attrs, join_data.registry_attrs)
  end

  defp catch_up_required?(nil, _current_event_sequence), do: false
  defp catch_up_required?(0, current_event_sequence), do: current_event_sequence > 0

  defp catch_up_required?(sequence, current_event_sequence) when is_integer(sequence),
    do: sequence < current_event_sequence

  defp catch_up_required?(_other, _current_event_sequence), do: false

  defp new_session_id(room_id) do
    "session-#{room_id}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
