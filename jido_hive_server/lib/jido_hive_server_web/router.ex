defmodule JidoHiveServerWeb.Router do
  use JidoHiveServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", JidoHiveServerWeb do
    pipe_through :api

    get "/targets", TargetController, :index
    post "/rooms", RoomController, :create
    get "/rooms/:id", RoomController, :show
    post "/rooms/:id/first_slice", RoomController, :run_first_slice
  end
end
