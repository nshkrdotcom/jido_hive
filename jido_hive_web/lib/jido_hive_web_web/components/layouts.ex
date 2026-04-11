defmodule JidoHiveWebWeb.Layouts do
  @moduledoc """
  Shared application layouts for the Jido Hive web operator surface.
  """
  use JidoHiveWebWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :eyebrow, :string, default: nil, doc: "small section label above the page title"
  attr :title, :string, required: true, doc: "primary page title"
  attr :subtitle, :string, default: nil, doc: "secondary page description"
  attr :active_nav, :string, default: "rooms", doc: "active shell navigation id"

  slot :actions, doc: "header action buttons"
  slot :header_meta, doc: "small metadata rendered beside the page title"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="ui-shell">
      <header class="ui-shell__header">
        <a href={~p"/rooms"} class="ui-brand">
          <span class="ui-brand__mark">JH</span>
          <span class="ui-brand__copy">
            <span class="ui-brand__eyebrow">Operator Surface</span>
            <span class="ui-brand__title">Jido Hive</span>
          </span>
        </a>

        <nav class="ui-shell__nav" aria-label="Primary">
          <a href={~p"/rooms"} class={nav_link_class(@active_nav == "rooms")}>
            Rooms
          </a>
        </nav>

        <div class="ui-shell__actions">
          {render_slot(@actions)}
        </div>
      </header>

      <main class="ui-shell__main">
        <section class="ui-screen-head">
          <div class="ui-screen-head__identity">
            <p :if={@eyebrow} class="ui-screen-head__eyebrow">{@eyebrow}</p>
            <h1 class="ui-screen-head__title">{@title}</h1>
            <p :if={@subtitle} class="ui-screen-head__subtitle">{@subtitle}</p>
          </div>

          <div :if={@header_meta != []} class="ui-screen-head__meta">
            {render_slot(@header_meta)}
          </div>
        </section>

        <section class="ui-shell__body">
          {render_slot(@inner_block)}
        </section>
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="Network unavailable"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Server unavailable"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  defp nav_link_class(true), do: "ui-shell__nav-link is-active"
  defp nav_link_class(false), do: "ui-shell__nav-link"
end
