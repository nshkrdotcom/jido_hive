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
    <Layouts.app
      flash={@flash}
      active_nav="rooms"
      eyebrow="Jido Hive Web"
      title="Room Workspaces"
      subtitle="Browser operator surface over the same room workflow seam used by the headless client and Switchyard TUI."
    >
      <:header_meta>
        <div class="ui-meta-row">
          <span class="ui-chip">API</span>
          <span class="ui-meta-value">{@api_base_url}</span>
        </div>
      </:header_meta>

      <div class="ui-page ui-page--index" data-screen="room-index">
        <section class="ui-ribbon">
          <div class="ui-ribbon__item">
            <p class="ui-ribbon__label">Current Surface</p>
            <p class="ui-ribbon__value">Shared operator seam</p>
          </div>
          <div class="ui-ribbon__item">
            <p class="ui-ribbon__label">Known Rooms</p>
            <p class="ui-ribbon__value">{length(@rooms)}</p>
          </div>
          <div class="ui-ribbon__item">
            <p class="ui-ribbon__label">Primary Action</p>
            <p class="ui-ribbon__value">Open a room or create a new one</p>
          </div>
        </section>

        <section class="ui-index-grid">
          <article class="ui-panel">
            <header class="ui-panel__header">
              <div>
                <p class="ui-panel__eyebrow">Workflow</p>
                <h2 class="ui-panel__title">Create Room</h2>
              </div>
              <p class="ui-panel__meta">Start a fresh operator workspace</p>
            </header>

            <div class="ui-panel__body">
              <.form id="create-room-form" for={@room_form} phx-submit="create_room" class="ui-form">
                <div class="ui-field">
                  <label class="ui-label" for={@room_form[:room_id].id}>Room ID</label>
                  <input
                    id={@room_form[:room_id].id}
                    type="text"
                    name={@room_form[:room_id].name}
                    value={@room_form[:room_id].value}
                    class="ui-input"
                    placeholder="room-123"
                  />
                  <p class="ui-field-hint">Leave blank to generate a durable room id.</p>
                </div>

                <div class="ui-field">
                  <label class="ui-label" for={@room_form[:brief].id}>Brief</label>
                  <textarea
                    id={@room_form[:brief].id}
                    name={@room_form[:brief].name}
                    class="ui-textarea ui-textarea--compact"
                    placeholder="What should the room solve?"
                  ><%= @room_form[:brief].value %></textarea>
                  <p :if={Map.has_key?(@create_errors, :brief)} class="ui-field-error">
                    {@create_errors.brief}
                  </p>
                </div>

                <div class="ui-form__actions">
                  <button type="submit" class="ui-button ui-button--primary">Create room</button>
                </div>
              </.form>
            </div>
          </article>

          <article class="ui-panel">
            <header class="ui-panel__header">
              <div>
                <p class="ui-panel__eyebrow">Room Catalog</p>
                <h2 class="ui-panel__title">Saved Rooms</h2>
              </div>
              <p class="ui-panel__meta">Known to the operator client for this API base</p>
            </header>

            <div class="ui-panel__body ui-panel__body--flush">
              <div :if={@rooms == []} class="ui-empty-state">
                <p class="ui-empty-state__title">No saved rooms yet</p>
                <p class="ui-empty-state__body">
                  Create a room or save one through the shared operator surface.
                </p>
              </div>

              <article :for={room <- @rooms} class="ui-room-card">
                <div class="ui-room-card__header">
                  <div class="ui-room-card__title-block">
                    <h3 class="ui-room-card__title">
                      <a href={~p"/rooms/#{room.room_id}"}>{room.brief}</a>
                    </h3>
                    <p class="ui-room-card__meta">{room.room_id}</p>
                  </div>
                  <span class={status_chip_class(room.status)}>{room.status}</span>
                </div>

                <dl class="ui-stats-grid">
                  <div class="ui-stat">
                    <dt>Slots</dt>
                    <dd>{room.completed_slots}/{room.total_slots}</dd>
                  </div>
                  <div class="ui-stat">
                    <dt>Participants</dt>
                    <dd>{room.participant_count}</dd>
                  </div>
                  <div class="ui-stat">
                    <dt>State</dt>
                    <dd>{if room.fetch_error, do: "fetch_error", else: "reachable"}</dd>
                  </div>
                </dl>

                <div class="ui-room-card__actions">
                  <a href={~p"/rooms/#{room.room_id}"} class="ui-button ui-button--secondary">Open</a>
                  <a href={~p"/rooms/#{room.room_id}/publish"} class="ui-button ui-button--ghost">
                    Publish
                  </a>
                </div>
              </article>
            </div>
          </article>

          <article class="ui-panel">
            <header class="ui-panel__header">
              <div>
                <p class="ui-panel__eyebrow">Operator Guide</p>
                <h2 class="ui-panel__title">What This Surface Does</h2>
              </div>
              <p class="ui-panel__meta">Same workflow truth, browser-native interaction</p>
            </header>

            <div class="ui-panel__body">
              <div class="ui-note-block">
                <h3>Core workflow</h3>
                <ul class="ui-bullet-list">
                  <li>Open a room to inspect workflow truth and the shared graph.</li>
                  <li>Send steering messages without bypassing the room session boundary.</li>
                  <li>Review publication readiness from the same shared operator surface.</li>
                </ul>
              </div>

              <div class="ui-note-block">
                <h3>Debugging order</h3>
                <ol class="ui-bullet-list ui-bullet-list--ordered">
                  <li>Server truth first.</li>
                  <li>Headless `jido_hive_client` second.</li>
                  <li>This web UI last.</li>
                </ol>
              </div>

              <div class="ui-note-block">
                <h3>Why this layout</h3>
                <p>
                  This screen uses pane-based composition so the browser surface can match the
                  operator posture of the TUI instead of collapsing into a document-centric CRUD page.
                </p>
              </div>
            </div>
          </article>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp status_chip_class("publication_ready"), do: "ui-status-chip ui-status-chip--success"
  defp status_chip_class("running"), do: "ui-status-chip ui-status-chip--info"
  defp status_chip_class("failed"), do: "ui-status-chip ui-status-chip--danger"
  defp status_chip_class("missing"), do: "ui-status-chip ui-status-chip--muted"
  defp status_chip_class(_status), do: "ui-status-chip"
end
