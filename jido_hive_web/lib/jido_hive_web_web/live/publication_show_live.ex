defmodule JidoHiveWebWeb.PublicationShowLive do
  use JidoHiveWebWeb, :live_view

  alias JidoHiveWeb.UIConfig

  @impl true
  def mount(%{"room_id" => room_id} = params, _session, socket) do
    identity = UIConfig.identity(params)
    publications_module = UIConfig.publications_module()
    api_base_url = UIConfig.api_base_url()

    workspace =
      publications_module.load_publication_workspace(
        api_base_url,
        room_id,
        identity.subject,
        []
      )

    {:ok,
     socket
     |> assign(:room_id, room_id)
     |> assign(:identity, identity)
     |> assign(:api_base_url, api_base_url)
     |> assign(:publications_module, publications_module)
     |> assign(:publication_workspace, workspace)
     |> assign(:bindings_form, to_form(default_bindings(workspace), as: :publish))}
  end

  @impl true
  def handle_event("publish", %{"publish" => bindings}, socket) do
    case socket.assigns.publications_module.publish(
           socket.assigns.api_base_url,
           socket.assigns.room_id,
           socket.assigns.publication_workspace,
           bindings,
           []
         ) do
      {:ok, _result} ->
        {:noreply, put_flash(socket, :info, "Publication submitted.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Publish failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl space-y-6 p-6">
      <header class="space-y-2">
        <div class="flex items-center justify-between gap-3">
          <div>
            <p class="text-sm uppercase tracking-[0.2em] text-zinc-500">Publication</p>
            <h1 class="text-3xl font-semibold text-zinc-900">Room {@room_id}</h1>
          </div>
          <a
            href={~p"/rooms/#{@room_id}"}
            class="rounded-md border border-zinc-300 px-3 py-2 text-sm font-medium text-zinc-900"
          >
            Back to room
          </a>
        </div>
        <p class="text-sm text-zinc-600">
          Review the publication workspace and submit bindings through the shared operator surface.
        </p>
      </header>

      <div class="grid gap-6 lg:grid-cols-[0.9fr_1.1fr]">
        <section class="space-y-4 rounded-xl border border-zinc-200 bg-white p-5 shadow-sm">
          <h2 class="text-lg font-semibold text-zinc-900">Readiness</h2>
          <ul class="space-y-2 text-sm text-zinc-700">
            <li :for={line <- @publication_workspace.readiness}>{line}</li>
          </ul>

          <div class="border-t border-zinc-200 pt-4">
            <h3 class="text-sm font-semibold text-zinc-900">Preview</h3>
            <div class="mt-2 space-y-2 rounded-lg bg-zinc-50 p-3 text-sm text-zinc-700">
              <p :for={line <- @publication_workspace.preview_lines}>{line}</p>
            </div>
          </div>
        </section>

        <section class="rounded-xl border border-zinc-200 bg-white p-5 shadow-sm">
          <h2 class="mb-4 text-lg font-semibold text-zinc-900">Bindings</h2>
          <.form id="publish-form" for={@bindings_form} phx-submit="publish" class="space-y-4">
            <div :for={channel <- @publication_workspace.channels} class="space-y-4">
              <h3 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">
                {channel.channel}
              </h3>

              <div :for={binding <- channel.required_bindings}>
                <label class="mb-1 block text-sm font-medium text-zinc-700">
                  {binding.description}
                </label>
                <input
                  type="text"
                  name={"publish[#{channel.channel}][#{binding.field}]"}
                  value={input_value(@bindings_form, channel.channel, binding.field)}
                  class="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
                />
              </div>
            </div>

            <button
              type="submit"
              class="rounded-md bg-zinc-900 px-4 py-2 text-sm font-medium text-white"
            >
              Publish
            </button>
          </.form>
        </section>
      </div>
    </div>
    """
  end

  defp default_bindings(workspace) do
    Enum.reduce(workspace.channels, %{}, fn channel, acc ->
      Map.put(
        acc,
        channel.channel,
        Map.new(channel.required_bindings, fn binding -> {binding.field, ""} end)
      )
    end)
  end

  defp input_value(form, channel, field) do
    form.params
    |> Map.get(channel, %{})
    |> Map.get(field, "")
  end
end
