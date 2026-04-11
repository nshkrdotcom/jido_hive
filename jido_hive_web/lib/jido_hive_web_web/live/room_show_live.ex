defmodule JidoHiveWebWeb.RoomShowLive do
  use JidoHiveWebWeb, :live_view

  alias JidoHiveClient.RoomWorkspace
  alias JidoHiveWeb.UIConfig

  @impl true
  def mount(%{"room_id" => room_id} = params, _session, socket) do
    identity = UIConfig.identity(params)
    rooms_module = UIConfig.rooms_module()
    room_session_module = UIConfig.room_session_module()
    api_base_url = UIConfig.api_base_url()

    workspace =
      rooms_module.load_room_workspace(api_base_url, room_id,
        participant_id: identity.participant_id
      )

    selected_context_id = workspace.selected_context_id

    socket =
      socket
      |> assign(:room_id, room_id)
      |> assign(:identity, identity)
      |> assign(:api_base_url, api_base_url)
      |> assign(:rooms_module, rooms_module)
      |> assign(:room_session_module, room_session_module)
      |> assign(:room_session, nil)
      |> assign(:raw_snapshot, nil)
      |> assign(:room_workspace, workspace)
      |> assign(:selected_context_id, selected_context_id)
      |> assign(:provenance, nil)
      |> assign(:draft_form, to_form(%{"text" => ""}, as: :draft))
      |> assign(
        :run_form,
        to_form(%{"max_assignments" => "", "assignment_timeout_ms" => ""}, as: :run)
      )
      |> assign(:run_errors, %{})

    if connected?(socket) do
      {:ok, session} =
        room_session_module.start_link(
          api_base_url: api_base_url,
          room_id: room_id,
          participant_id: identity.participant_id,
          participant_role: identity.participant_role,
          authority_level: identity.authority_level
        )

      :ok = room_session_module.subscribe(session)
      _ = room_session_module.refresh(session)

      {:ok, assign(socket, :room_session, session)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if session = socket.assigns[:room_session] do
      _ = socket.assigns.room_session_module.shutdown(session)
    end

    :ok
  end

  @impl true
  def handle_info(
        {:room_session_snapshot, room_id, snapshot},
        %{assigns: %{room_id: room_id}} = socket
      ) do
    selected_context_id =
      socket.assigns.selected_context_id ||
        workspace_selected_context(snapshot, socket.assigns.identity.participant_id)

    {:noreply,
     socket
     |> assign(:raw_snapshot, snapshot)
     |> assign(
       :room_workspace,
       build_workspace(snapshot, selected_context_id, socket.assigns.identity.participant_id)
     )
     |> assign(:selected_context_id, selected_context_id)}
  end

  @impl true
  def handle_info(
        {:client_runtime_event, %{room_id: room_id}},
        %{assigns: %{room_id: room_id}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_info({:client_runtime_event, _event}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_context", %{"context_id" => context_id}, socket) do
    room_workspace =
      case socket.assigns.raw_snapshot do
        %{} = snapshot ->
          build_workspace(snapshot, context_id, socket.assigns.identity.participant_id)

        _other ->
          socket.assigns.rooms_module.load_room_workspace(
            socket.assigns.api_base_url,
            socket.assigns.room_id,
            participant_id: socket.assigns.identity.participant_id,
            selected_context_id: context_id
          )
      end

    {:noreply,
     socket
     |> assign(:selected_context_id, context_id)
     |> assign(:room_workspace, room_workspace)}
  end

  def handle_event("show_provenance", _params, %{assigns: %{selected_context_id: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("show_provenance", _params, socket) do
    context_id = socket.assigns.selected_context_id

    provenance =
      case socket.assigns.raw_snapshot do
        %{} = snapshot ->
          RoomWorkspace.provenance(snapshot, context_id)

        _other ->
          socket.assigns.rooms_module.load_provenance(
            socket.assigns.api_base_url,
            socket.assigns.room_id,
            context_id,
            []
          )
      end

    {:noreply, assign(socket, :provenance, provenance)}
  end

  def handle_event("hide_provenance", _params, socket) do
    {:noreply, assign(socket, :provenance, nil)}
  end

  def handle_event("submit_draft", %{"draft" => %{"text" => text}}, socket) do
    text = String.trim(text)

    cond do
      text == "" ->
        {:noreply, put_flash(socket, :error, "Draft cannot be blank.")}

      session = socket.assigns.room_session ->
        case socket.assigns.room_session_module.submit_chat(session, %{text: text}) do
          {:ok, _result} ->
            {:noreply,
             socket
             |> assign(:draft_form, to_form(%{"text" => ""}, as: :draft))
             |> put_flash(:info, "Steering message submitted.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Submit failed: #{inspect(reason)}")}
        end

      true ->
        case socket.assigns.rooms_module.submit_steering(
               socket.assigns.api_base_url,
               socket.assigns.room_id,
               socket.assigns.identity,
               text,
               []
             ) do
          {:ok, _result} ->
            {:noreply,
             socket
             |> assign(:draft_form, to_form(%{"text" => ""}, as: :draft))
             |> put_flash(:info, "Steering message submitted.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Submit failed: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("run_room", %{"run" => attrs}, socket) do
    rooms_module = socket.assigns.rooms_module

    with {:ok, opts} <- rooms_module.normalize_run_attrs(attrs),
         {:ok, operation} <-
           rooms_module.run_room(socket.assigns.api_base_url, socket.assigns.room_id, opts) do
      {:noreply,
       socket
       |> assign(:run_errors, %{})
       |> assign(:run_form, to_form(attrs, as: :run))
       |> put_flash(:info, "Run requested: #{operation["operation_id"]}")}
    else
      {:error, errors} when is_map(errors) ->
        {:noreply,
         socket
         |> assign(:run_errors, errors)
         |> assign(:run_form, to_form(attrs, as: :run))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Run failed: #{inspect(reason)}")}
    end
  end

  def handle_event("refresh_room", _params, socket) do
    case socket.assigns.room_session do
      nil ->
        workspace =
          socket.assigns.rooms_module.load_room_workspace(
            socket.assigns.api_base_url,
            socket.assigns.room_id,
            participant_id: socket.assigns.identity.participant_id,
            selected_context_id: socket.assigns.selected_context_id
          )

        {:noreply, assign(socket, :room_workspace, workspace)}

      session ->
        _ = socket.assigns.room_session_module.refresh(session)
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      active_nav="rooms"
      eyebrow="Room Workspace"
      title={@room_workspace.objective}
      subtitle="Full-screen operator workspace over the shared room-session seam."
    >
      <:actions>
        <button phx-click="refresh_room" class="ui-button ui-button--ghost">
          Refresh
        </button>
        <a href={~p"/rooms/#{@room_id}/publish"} class="ui-button ui-button--primary">
          Publish
        </a>
      </:actions>

      <:header_meta>
        <div class="ui-meta-grid">
          <div class="ui-meta-row">
            <span class="ui-chip">Room</span>
            <span class="ui-meta-value mono">{@room_id}</span>
          </div>
          <div class="ui-meta-row">
            <span class="ui-chip">Operator</span>
            <span class="ui-meta-value">
              {@identity.participant_id} · {@identity.participant_role}
            </span>
          </div>
        </div>
      </:header_meta>

      <div class="ui-page ui-page--room" data-screen="room-show">
        <section class="ui-ribbon">
          <div class="ui-ribbon__item">
            <p class="ui-ribbon__label">Stage</p>
            <p class="ui-ribbon__value">{@room_workspace.control_plane.stage}</p>
          </div>
          <div class="ui-ribbon__item">
            <p class="ui-ribbon__label">Next Action</p>
            <p class="ui-ribbon__value">{@room_workspace.control_plane.next_action}</p>
          </div>
          <div class="ui-ribbon__item">
            <p class="ui-ribbon__label">Why</p>
            <p class="ui-ribbon__value ui-ribbon__value--wrap">
              {@room_workspace.control_plane.reason}
            </p>
          </div>
          <div class="ui-ribbon__item">
            <p class="ui-ribbon__label">Publish Ready</p>
            <p class="ui-ribbon__value">
              <span class={publish_ready_class(@room_workspace.control_plane.publish_ready)}>
                {publish_ready_label(@room_workspace.control_plane.publish_ready)}
              </span>
            </p>
          </div>
        </section>

        <section class="ui-room-grid">
          <div class="ui-room-column">
            <article class="ui-panel ui-panel--fill">
              <header class="ui-panel__header">
                <div>
                  <p class="ui-panel__eyebrow">Transcript</p>
                  <h2 class="ui-panel__title">Conversation</h2>
                </div>
                <p class="ui-panel__meta">{length(@room_workspace.conversation)} entries</p>
              </header>

              <div class="ui-panel__body">
                <div :if={@room_workspace.conversation == []} class="ui-empty-state">
                  <p class="ui-empty-state__title">No conversation yet</p>
                  <p class="ui-empty-state__body">
                    Use the steering composer below to push the room forward.
                  </p>
                </div>

                <div :if={@room_workspace.conversation != []} class="ui-feed">
                  <article :for={entry <- @room_workspace.conversation} class="ui-feed__item">
                    <div class="ui-feed__meta">
                      <span class="ui-feed__author">{entry.participant_id}</span>
                      <span class="ui-feed__kind">{entry.contribution_type}</span>
                    </div>
                    <p class="ui-feed__body">{entry.body}</p>
                  </article>
                </div>
              </div>
            </article>

            <article class="ui-panel ui-panel--fill">
              <header class="ui-panel__header">
                <div>
                  <p class="ui-panel__eyebrow">Timeline</p>
                  <h2 class="ui-panel__title">Events</h2>
                </div>
                <p class="ui-panel__meta">{length(@room_workspace.events)} events</p>
              </header>

              <div class="ui-panel__body">
                <div :if={@room_workspace.events == []} class="ui-empty-state">
                  <p class="ui-empty-state__title">No room events yet</p>
                  <p class="ui-empty-state__body">Refresh after the next run or operator action.</p>
                </div>

                <div :if={@room_workspace.events != []} class="ui-feed ui-feed--dense">
                  <article
                    :for={event <- @room_workspace.events}
                    class="ui-feed__item ui-feed__item--event"
                  >
                    <div class="ui-feed__meta">
                      <span class="ui-feed__kind">{event.kind}</span>
                      <span class="ui-feed__status">{event.status}</span>
                    </div>
                    <p class="ui-feed__body">{event.body}</p>
                  </article>
                </div>
              </div>
            </article>
          </div>

          <article class="ui-panel ui-panel--fill">
            <header class="ui-panel__header">
              <div>
                <p class="ui-panel__eyebrow">Shared Context</p>
                <h2 class="ui-panel__title">Shared Graph</h2>
              </div>
              <button
                id="show-provenance"
                phx-click="show_provenance"
                class="ui-button ui-button--ghost ui-button--compact"
              >
                Provenance
              </button>
            </header>

            <div class="ui-panel__body ui-panel__body--flush">
              <div :for={section <- @room_workspace.graph_sections} class="ui-graph-section">
                <div class="ui-graph-section__header">
                  <h3 class="ui-graph-section__title">{section.title}</h3>
                  <span class="ui-graph-section__count">{length(section.items)}</span>
                </div>

                <div class="ui-graph-list">
                  <button
                    :for={item <- section.items}
                    id={"context-#{item.context_id}"}
                    phx-click="select_context"
                    phx-value-context_id={item.context_id}
                    class={context_item_class(item.context_id == @selected_context_id)}
                  >
                    <div class="ui-graph-item__header">
                      <h4 class="ui-graph-item__title">{item.title}</h4>
                      <span class="ui-graph-item__counts">
                        {item.graph.incoming}/{item.graph.outgoing}
                      </span>
                    </div>

                    <div class="ui-context-tags">
                      <span :if={item.flags.binding} class="ui-context-tag ui-context-tag--accent">
                        Binding
                      </span>
                      <span :if={item.flags.conflict} class="ui-context-tag ui-context-tag--danger">
                        Conflict
                      </span>
                      <span :if={item.flags.stale} class="ui-context-tag ui-context-tag--warning">
                        Stale
                      </span>
                      <span
                        :if={(item.flags.duplicate_count || 0) > 0}
                        class="ui-context-tag ui-context-tag--muted"
                      >
                        Duplicates {item.flags.duplicate_count}
                      </span>
                    </div>
                  </button>
                </div>
              </div>
            </div>
          </article>

          <div class="ui-room-column ui-room-column--side">
            <article class="ui-panel ui-panel--fill">
              <header class="ui-panel__header">
                <div>
                  <p class="ui-panel__eyebrow">Selection</p>
                  <h2 class="ui-panel__title">Selected Detail</h2>
                </div>
                <p class="ui-panel__meta">
                  {if @selected_context_id, do: @selected_context_id, else: "No selection"}
                </p>
              </header>

              <div class="ui-panel__body">
                <%= if detail = @room_workspace.selected_detail do %>
                  <div class="ui-detail-stack">
                    <div class="ui-detail-block">
                      <p class="ui-detail-block__label">Title</p>
                      <p class="ui-detail-block__value">{detail.title}</p>
                    </div>

                    <div class="ui-detail-block">
                      <p class="ui-detail-block__label">Body</p>
                      <p class="ui-detail-block__body">{detail.body}</p>
                    </div>

                    <div class="ui-detail-block">
                      <p class="ui-detail-block__label">Recommended Actions</p>
                      <div class="ui-action-list">
                        <span
                          :for={action <- detail.recommended_actions}
                          class="ui-action-chip"
                        >
                          {action.label}
                        </span>
                      </div>
                    </div>

                    <div
                      :if={@room_workspace.control_plane.publish_blockers != []}
                      class="ui-note-block"
                    >
                      <h3>Publish blockers</h3>
                      <ul class="ui-bullet-list">
                        <li :for={blocker <- @room_workspace.control_plane.publish_blockers}>
                          {blocker}
                        </li>
                      </ul>
                    </div>
                  </div>
                <% else %>
                  <div class="ui-empty-state">
                    <p class="ui-empty-state__title">No context selected</p>
                    <p class="ui-empty-state__body">
                      Choose a graph object to inspect its body and recommended actions.
                    </p>
                  </div>
                <% end %>
              </div>
            </article>

            <article class="ui-panel">
              <header class="ui-panel__header">
                <div>
                  <p class="ui-panel__eyebrow">Execution</p>
                  <h2 class="ui-panel__title">Run Room</h2>
                </div>
                <p class="ui-panel__meta">Queue additional assignments</p>
              </header>

              <div class="ui-panel__body">
                <.form id="run-room-form" for={@run_form} phx-submit="run_room" class="ui-form">
                  <div class="ui-field">
                    <label class="ui-label" for={@run_form[:max_assignments].id}>
                      Max Assignments
                    </label>
                    <input
                      id={@run_form[:max_assignments].id}
                      type="text"
                      name={@run_form[:max_assignments].name}
                      value={@run_form[:max_assignments].value}
                      class="ui-input"
                    />
                    <p
                      :if={Map.has_key?(@run_errors, :max_assignments)}
                      class="ui-field-error"
                    >
                      {@run_errors.max_assignments}
                    </p>
                  </div>

                  <div class="ui-field">
                    <label class="ui-label" for={@run_form[:assignment_timeout_ms].id}>
                      Assignment Timeout (ms)
                    </label>
                    <input
                      id={@run_form[:assignment_timeout_ms].id}
                      type="text"
                      name={@run_form[:assignment_timeout_ms].name}
                      value={@run_form[:assignment_timeout_ms].value}
                      class="ui-input"
                    />
                  </div>

                  <div class="ui-form__actions">
                    <button type="submit" class="ui-button ui-button--secondary">Run room</button>
                  </div>
                </.form>
              </div>
            </article>
          </div>
        </section>

        <article class="ui-panel ui-panel--composer">
          <header class="ui-panel__header">
            <div>
              <p class="ui-panel__eyebrow">Operator Action</p>
              <h2 class="ui-panel__title">Steering Composer</h2>
            </div>
            <p class="ui-panel__meta">Submit room guidance through the shared session boundary</p>
          </header>

          <div class="ui-panel__body">
            <.form id="draft-form" for={@draft_form} phx-submit="submit_draft" class="ui-form">
              <div class="ui-field">
                <label class="ui-label" for={@draft_form[:text].id}>Steering Message</label>
                <textarea
                  id={@draft_form[:text].id}
                  name={@draft_form[:text].name}
                  class="ui-textarea"
                  placeholder="Tell the room what to clarify, decide, or run next."
                ><%= @draft_form[:text].value %></textarea>
              </div>

              <div class="ui-form__actions">
                <button type="submit" class="ui-button ui-button--primary">
                  Submit steering
                </button>
              </div>
            </.form>
          </div>
        </article>
      </div>

      <section :if={match?({:ok, _}, @provenance)} id="provenance-modal" class="ui-overlay">
        <% {:ok, provenance} = @provenance %>
        <button phx-click="hide_provenance" class="ui-overlay__backdrop" aria-label="Close provenance">
        </button>
        <article class="ui-overlay__card">
          <header class="ui-panel__header ui-panel__header--overlay">
            <div>
              <p class="ui-panel__eyebrow">Trace</p>
              <h2 class="ui-panel__title">Provenance</h2>
            </div>
            <button phx-click="hide_provenance" class="ui-button ui-button--ghost ui-button--compact">
              Close
            </button>
          </header>

          <div class="ui-overlay__body">
            <div class="ui-detail-block">
              <p class="ui-detail-block__label">Selected Context</p>
              <p class="ui-detail-block__value">{provenance.title}</p>
            </div>

            <div class="ui-detail-block">
              <p class="ui-detail-block__label">Recommended Actions</p>
              <div class="ui-action-list">
                <span :for={action <- provenance.recommended_actions} class="ui-action-chip">
                  {action.label}
                </span>
              </div>
            </div>

            <div class="ui-detail-block">
              <p class="ui-detail-block__label">Trace</p>
              <ol class="ui-provenance-trace">
                <li :for={step <- provenance.trace}>
                  <span class="ui-provenance-trace__depth">Depth {step.depth}</span>
                  <span class="ui-provenance-trace__title">{step.title}</span>
                </li>
              </ol>
            </div>
          </div>
        </article>
      </section>
    </Layouts.app>
    """
  end

  defp build_workspace(snapshot, selected_context_id, participant_id) do
    RoomWorkspace.build(snapshot,
      selected_context_id: selected_context_id,
      participant_id: participant_id
    )
  end

  defp workspace_selected_context(snapshot, participant_id) do
    build_workspace(snapshot, nil, participant_id).selected_context_id
  end

  defp publish_ready_label(true), do: "Ready"
  defp publish_ready_label(false), do: "Blocked"

  defp publish_ready_class(true), do: "ui-status-chip ui-status-chip--success"
  defp publish_ready_class(false), do: "ui-status-chip ui-status-chip--danger"

  defp context_item_class(true), do: "ui-graph-item is-active"
  defp context_item_class(false), do: "ui-graph-item"
end
