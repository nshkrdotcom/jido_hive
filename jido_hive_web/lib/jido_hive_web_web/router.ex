defmodule JidoHiveWebWeb.Router do
  use JidoHiveWebWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JidoHiveWebWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", JidoHiveWebWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/rooms", RoomIndexLive
    live "/rooms/:room_id", RoomShowLive
    live "/rooms/:room_id/publish", PublicationShowLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", JidoHiveWebWeb do
  #   pipe_through :api
  # end
end
