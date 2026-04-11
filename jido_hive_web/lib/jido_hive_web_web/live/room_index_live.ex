defmodule JidoHiveWebWeb.RoomIndexLive do
  use JidoHiveWebWeb, :live_view

  alias JidoHiveWeb.UIConfig

  @impl true
  def mount(_params, _session, socket) do
    rooms_module = UIConfig.rooms_module()
    api_base_url = UIConfig.api_base_url()

    {:ok,
     socket
     |> assign(:api_base_url, api_base_url)
     |> assign(:rooms_module, rooms_module)
     |> assign(:rooms, rooms_module.list_rooms(api_base_url, []))
     |> assign(:create_errors, %{})
     |> assign(:room_form, to_form(%{"room_id" => "", "brief" => ""}, as: :room))}
  end

  @impl true
  def handle_event("create_room", %{"room" => attrs}, socket) do
    rooms_module = socket.assigns.rooms_module

    with {:ok, payload} <- rooms_module.normalize_create_attrs(attrs),
         {:ok, room} <- rooms_module.create_room(socket.assigns.api_base_url, payload, []) do
      room_id = Map.get(room, "room_id") || Map.get(room, :room_id) || payload["room_id"]

      {:noreply,
       socket
       |> put_flash(:info, "Room created.")
       |> push_navigate(to: ~p"/rooms/#{room_id}")}
    else
      {:error, errors} when is_map(errors) ->
        {:noreply,
         socket
         |> assign(:create_errors, errors)
         |> assign(:room_form, to_form(attrs, as: :room))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Room create failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl space-y-8 p-6">
      <header class="space-y-2">
        <p class="text-sm uppercase tracking-[0.2em] text-zinc-500">Jido Hive Web</p>
        <h1 class="text-3xl font-semibold text-zinc-900">Rooms</h1>
        <p class="max-w-3xl text-sm text-zinc-600">
          Browser operator surface over the same room workflow seam used by the headless client and Switchyard TUI.
        </p>
      </header>

      <section class="rounded-xl border border-zinc-200 bg-white p-5 shadow-sm">
        <div class="mb-4">
          <h2 class="text-lg font-semibold text-zinc-900">Create Room</h2>
          <p class="text-sm text-zinc-600">
            Create a room directly from the browser without bypassing the shared operator surface.
          </p>
        </div>

        <.form
          id="create-room-form"
          for={@room_form}
          phx-submit="create_room"
          class="grid gap-4 md:grid-cols-2"
        >
          <div>
            <label class="mb-1 block text-sm font-medium text-zinc-700">Room ID</label>
            <input
              type="text"
              name={@room_form[:room_id].name}
              value={@room_form[:room_id].value}
              class="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
              placeholder="room-123"
            />
          </div>

          <div>
            <label class="mb-1 block text-sm font-medium text-zinc-700">Brief</label>
            <input
              type="text"
              name={@room_form[:brief].name}
              value={@room_form[:brief].value}
              class="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
              placeholder="What should the room solve?"
            />
            <p :if={Map.has_key?(@create_errors, :brief)} class="mt-1 text-sm text-rose-600">
              {@create_errors.brief}
            </p>
          </div>

          <div class="md:col-span-2">
            <button
              type="submit"
              class="rounded-md bg-zinc-900 px-4 py-2 text-sm font-medium text-white"
            >
              Create room
            </button>
          </div>
        </.form>
      </section>

      <section class="space-y-4">
        <div>
          <h2 class="text-lg font-semibold text-zinc-900">Saved Rooms</h2>
          <p class="text-sm text-zinc-600">
            Rooms known to the operator client for the current API base URL.
          </p>
        </div>

        <div class="grid gap-4">
          <article
            :for={room <- @rooms}
            class="rounded-xl border border-zinc-200 bg-white p-5 shadow-sm"
          >
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div class="space-y-1">
                <h3 class="text-lg font-semibold text-zinc-900">
                  <a href={~p"/rooms/#{room.room_id}"} class="hover:underline">{room.brief}</a>
                </h3>
                <p class="text-sm text-zinc-600">{room.room_id}</p>
              </div>

              <div class="rounded-full bg-zinc-100 px-3 py-1 text-sm font-medium text-zinc-700">
                {room.status}
              </div>
            </div>

            <dl class="mt-4 grid gap-3 text-sm text-zinc-600 md:grid-cols-3">
              <div>
                <dt class="font-medium text-zinc-800">Slots</dt>
                <dd>{room.completed_slots}/{room.total_slots}</dd>
              </div>
              <div>
                <dt class="font-medium text-zinc-800">Participants</dt>
                <dd>{room.participant_count}</dd>
              </div>
              <div>
                <dt class="font-medium text-zinc-800">Actions</dt>
                <dd class="space-x-3">
                  <a
                    href={~p"/rooms/#{room.room_id}"}
                    class="font-medium text-zinc-900 hover:underline"
                  >
                    Open
                  </a>
                  <a
                    href={~p"/rooms/#{room.room_id}/publish"}
                    class="font-medium text-zinc-900 hover:underline"
                  >
                    Publish
                  </a>
                </dd>
              </div>
            </dl>
          </article>
        </div>
      </section>
    </div>
    """
  end
end
