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
    <div class="mx-auto max-w-7xl space-y-6 p-6">
      <header class="space-y-2">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p class="text-sm uppercase tracking-[0.2em] text-zinc-500">Room Workspace</p>
            <h1 class="text-3xl font-semibold text-zinc-900">{@room_workspace.objective}</h1>
          </div>
          <div class="flex gap-3 text-sm">
            <button
              phx-click="refresh_room"
              class="rounded-md border border-zinc-300 px-3 py-2 font-medium text-zinc-800"
            >
              Refresh
            </button>
            <a
              href={~p"/rooms/#{@room_id}/publish"}
              class="rounded-md bg-zinc-900 px-3 py-2 font-medium text-white"
            >
              Publish
            </a>
          </div>
        </div>

        <div class="grid gap-3 rounded-xl border border-zinc-200 bg-white p-5 shadow-sm md:grid-cols-4">
          <div>
            <p class="text-xs uppercase tracking-wide text-zinc-500">Stage</p>
            <p class="text-sm font-medium text-zinc-900">{@room_workspace.control_plane.stage}</p>
          </div>
          <div>
            <p class="text-xs uppercase tracking-wide text-zinc-500">Next Action</p>
            <p class="text-sm font-medium text-zinc-900">
              {@room_workspace.control_plane.next_action}
            </p>
          </div>
          <div>
            <p class="text-xs uppercase tracking-wide text-zinc-500">Why</p>
            <p class="text-sm text-zinc-700">{@room_workspace.control_plane.reason}</p>
          </div>
          <div>
            <p class="text-xs uppercase tracking-wide text-zinc-500">Publish Ready</p>
            <p class="text-sm font-medium text-zinc-900">
              {@room_workspace.control_plane.publish_ready}
            </p>
          </div>
        </div>
      </header>

      <div class="grid gap-6 xl:grid-cols-[1.1fr_1fr_0.9fr]">
        <section class="space-y-4 rounded-xl border border-zinc-200 bg-white p-5 shadow-sm">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold text-zinc-900">Conversation</h2>
            <span class="text-sm text-zinc-500">{length(@room_workspace.conversation)} entries</span>
          </div>

          <div class="space-y-3">
            <article
              :for={entry <- @room_workspace.conversation}
              class="rounded-lg bg-zinc-50 p-3 text-sm"
            >
              <p class="font-medium text-zinc-900">
                {entry.participant_id} · {entry.contribution_type}
              </p>
              <p class="mt-1 text-zinc-700">{entry.body}</p>
            </article>
          </div>

          <.form id="draft-form" for={@draft_form} phx-submit="submit_draft" class="space-y-2">
            <label class="block text-sm font-medium text-zinc-700">Steering Message</label>
            <textarea
              name={@draft_form[:text].name}
              class="min-h-28 w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
            ><%= @draft_form[:text].value %></textarea>
            <button
              type="submit"
              class="rounded-md bg-zinc-900 px-4 py-2 text-sm font-medium text-white"
            >
              Submit steering
            </button>
          </.form>
        </section>

        <section class="space-y-4 rounded-xl border border-zinc-200 bg-white p-5 shadow-sm">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold text-zinc-900">Shared Graph</h2>
            <button
              id="show-provenance"
              phx-click="show_provenance"
              class="text-sm font-medium text-zinc-900 hover:underline"
            >
              Provenance
            </button>
          </div>

          <div :for={section <- @room_workspace.graph_sections} class="space-y-2">
            <h3 class="text-xs font-semibold uppercase tracking-wide text-zinc-500">
              {section.title}
            </h3>
            <button
              :for={item <- section.items}
              id={"context-#{item.context_id}"}
              phx-click="select_context"
              phx-value-context_id={item.context_id}
              class={[
                "w-full rounded-lg border px-3 py-2 text-left text-sm",
                if(item.context_id == @selected_context_id,
                  do: "border-zinc-900 bg-zinc-100 text-zinc-900",
                  else: "border-zinc-200 bg-white text-zinc-700"
                )
              ]}
            >
              <div class="font-medium">{item.title}</div>
            </button>
          </div>
        </section>

        <section class="space-y-4 rounded-xl border border-zinc-200 bg-white p-5 shadow-sm">
          <h2 class="text-lg font-semibold text-zinc-900">Selected Detail</h2>

          <%= if detail = @room_workspace.selected_detail do %>
            <div class="space-y-3">
              <div>
                <p class="text-xs uppercase tracking-wide text-zinc-500">Title</p>
                <p class="text-sm font-medium text-zinc-900">{detail.title}</p>
              </div>
              <div>
                <p class="text-xs uppercase tracking-wide text-zinc-500">Body</p>
                <p class="text-sm text-zinc-700">{detail.body}</p>
              </div>

              <div>
                <p class="text-xs uppercase tracking-wide text-zinc-500">Recommended Actions</p>
                <ul class="mt-1 space-y-1 text-sm text-zinc-700">
                  <li :for={action <- detail.recommended_actions}>{action.label}</li>
                </ul>
              </div>
            </div>
          <% else %>
            <p class="text-sm text-zinc-600">No context selected.</p>
          <% end %>

          <div class="border-t border-zinc-200 pt-4">
            <h3 class="mb-2 text-sm font-semibold text-zinc-900">Run Room</h3>
            <.form id="run-room-form" for={@run_form} phx-submit="run_room" class="space-y-3">
              <div>
                <label class="mb-1 block text-sm font-medium text-zinc-700">Max Assignments</label>
                <input
                  type="text"
                  name={@run_form[:max_assignments].name}
                  value={@run_form[:max_assignments].value}
                  class="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
                />
                <p
                  :if={Map.has_key?(@run_errors, :max_assignments)}
                  class="mt-1 text-sm text-rose-600"
                >
                  {@run_errors.max_assignments}
                </p>
              </div>

              <div>
                <label class="mb-1 block text-sm font-medium text-zinc-700">
                  Assignment Timeout (ms)
                </label>
                <input
                  type="text"
                  name={@run_form[:assignment_timeout_ms].name}
                  value={@run_form[:assignment_timeout_ms].value}
                  class="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
                />
              </div>

              <button
                type="submit"
                class="rounded-md border border-zinc-900 px-4 py-2 text-sm font-medium text-zinc-900"
              >
                Run room
              </button>
            </.form>
          </div>
        </section>
      </div>

      <section
        :if={match?({:ok, _}, @provenance)}
        id="provenance-modal"
        class="rounded-xl border border-zinc-200 bg-white p-5 shadow-sm"
      >
        <% {:ok, provenance} = @provenance %>
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-zinc-900">Provenance</h2>
          <button
            phx-click="hide_provenance"
            class="text-sm font-medium text-zinc-900 hover:underline"
          >
            Close
          </button>
        </div>

        <p class="text-sm font-medium text-zinc-900">{provenance.title}</p>
        <ul class="mt-3 space-y-1 text-sm text-zinc-700">
          <li :for={action <- provenance.recommended_actions}>{action.label}</li>
        </ul>
      </section>
    </div>
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
end
