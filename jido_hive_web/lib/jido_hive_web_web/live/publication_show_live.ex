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
    <Layouts.app
      flash={@flash}
      active_nav="rooms"
      eyebrow="Publication Workspace"
      title={"Room #{@room_id}"}
      subtitle="Review readiness, confirm bindings, and publish the canonical draft from the same shared operator seam."
    >
      <:actions>
        <a href={~p"/rooms/#{@room_id}"} class="ui-button ui-button--ghost">
          Back to room
        </a>
      </:actions>

      <:header_meta>
        <div class="ui-meta-grid">
          <div class="ui-meta-row">
            <span class="ui-chip">Subject</span>
            <span class="ui-meta-value">{@identity.subject}</span>
          </div>
          <div class="ui-meta-row">
            <span class="ui-chip">Duplicate Policy</span>
            <span class="ui-meta-value">{@publication_workspace.duplicate_policy}</span>
          </div>
        </div>
      </:header_meta>

      <div class="ui-page ui-page--publication" data-screen="publication-show">
        <section class="ui-ribbon">
          <div class="ui-ribbon__item">
            <p class="ui-ribbon__label">Channel Count</p>
            <p class="ui-ribbon__value">{length(@publication_workspace.channels)}</p>
          </div>
          <div class="ui-ribbon__item">
            <p class="ui-ribbon__label">Primary Channel</p>
            <p class="ui-ribbon__value">
              {if @publication_workspace.selected_channel,
                do: @publication_workspace.selected_channel.channel,
                else: "None"}
            </p>
          </div>
          <div class="ui-ribbon__item">
            <p class="ui-ribbon__label">Source Entries</p>
            <p class="ui-ribbon__value">{Enum.join(@publication_workspace.source_entries, ", ")}</p>
          </div>
          <div class="ui-ribbon__item">
            <p class="ui-ribbon__label">Ready State</p>
            <p class="ui-ribbon__value">
              <span class={ready_chip_class(@publication_workspace.ready?)}>
                {ready_label(@publication_workspace.ready?)}
              </span>
            </p>
          </div>
        </section>

        <section class="ui-publication-grid">
          <div class="ui-publication-column">
            <article class="ui-panel ui-panel--fill">
              <header class="ui-panel__header">
                <div>
                  <p class="ui-panel__eyebrow">Readiness</p>
                  <h2 class="ui-panel__title">Publish Checks</h2>
                </div>
                <p class="ui-panel__meta">Server-derived publish workspace</p>
              </header>

              <div class="ui-panel__body">
                <div class="ui-note-block">
                  <h3>Checklist</h3>
                  <ul class="ui-bullet-list">
                    <li :for={line <- @publication_workspace.readiness}>{line}</li>
                  </ul>
                </div>

                <div class="ui-note-block">
                  <h3>Channels</h3>
                  <div class="ui-action-list">
                    <span
                      :for={channel <- @publication_workspace.channels}
                      class={channel_chip_class(channel.selected?)}
                    >
                      {channel.channel}
                    </span>
                  </div>
                </div>
              </div>
            </article>

            <article class="ui-panel ui-panel--fill">
              <header class="ui-panel__header">
                <div>
                  <p class="ui-panel__eyebrow">Output</p>
                  <h2 class="ui-panel__title">Preview</h2>
                </div>
                <p class="ui-panel__meta">Canonical publication draft</p>
              </header>

              <div class="ui-panel__body">
                <div class="ui-preview-card">
                  <p :for={line <- @publication_workspace.preview_lines} class="ui-preview-card__line">
                    {line}
                  </p>
                </div>
              </div>
            </article>
          </div>

          <article class="ui-panel ui-panel--fill">
            <header class="ui-panel__header">
              <div>
                <p class="ui-panel__eyebrow">Bindings</p>
                <h2 class="ui-panel__title">Publish Controls</h2>
              </div>
              <p class="ui-panel__meta">Supply per-channel required fields</p>
            </header>

            <div class="ui-panel__body">
              <.form id="publish-form" for={@bindings_form} phx-submit="publish" class="ui-form">
                <section :for={channel <- @publication_workspace.channels} class="ui-binding-group">
                  <div class="ui-binding-group__header">
                    <div>
                      <h3 class="ui-binding-group__title">{channel.channel}</h3>
                      <p class="ui-binding-group__meta">
                        {if channel.auth.status == :cached,
                          do: "Connection ready",
                          else: "Connection check required"}
                      </p>
                    </div>
                    <span class={channel_chip_class(channel.selected?)}>{channel.channel}</span>
                  </div>

                  <div class="ui-binding-group__body">
                    <div :for={binding <- channel.required_bindings} class="ui-field">
                      <label class="ui-label">
                        {binding.description}
                      </label>
                      <input
                        type="text"
                        name={"publish[#{channel.channel}][#{binding.field}]"}
                        value={input_value(@bindings_form, channel.channel, binding.field)}
                        class="ui-input"
                      />
                    </div>

                    <div :if={channel.draft != %{}} class="ui-note-block">
                      <h3>Draft snapshot</h3>
                      <ul class="ui-bullet-list">
                        <li :for={{field, value} <- channel.draft}>
                          <span class="ui-draft-field">{field}</span>
                          <pre class="ui-draft-value">{draft_value(value)}</pre>
                        </li>
                      </ul>
                    </div>
                  </div>
                </section>

                <div class="ui-form__actions ui-form__actions--spread">
                  <p class="ui-field-hint">
                    Submit the publication using the canonical workspace bindings above.
                  </p>
                  <button type="submit" class="ui-button ui-button--primary">Publish</button>
                </div>
              </.form>
            </div>
          </article>
        </section>
      </div>
    </Layouts.app>
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

  defp ready_label(true), do: "Ready"
  defp ready_label(false), do: "Blocked"

  defp ready_chip_class(true), do: "ui-status-chip ui-status-chip--success"
  defp ready_chip_class(false), do: "ui-status-chip ui-status-chip--danger"

  defp channel_chip_class(true), do: "ui-action-chip ui-action-chip--accent"
  defp channel_chip_class(false), do: "ui-action-chip"

  defp draft_value(value) when is_binary(value), do: value
  defp draft_value(value) when is_number(value), do: to_string(value)
  defp draft_value(true), do: "true"
  defp draft_value(false), do: "false"
  defp draft_value(nil), do: "null"

  defp draft_value(value) do
    Jason.encode!(value, pretty: true)
  rescue
    _error -> inspect(value, pretty: true, limit: :infinity)
  end
end
