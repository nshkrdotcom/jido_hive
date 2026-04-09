defmodule JidoHiveServerWeb.Router do
  use JidoHiveServerWeb, :router

  scope "/", JidoHiveServerWeb do
    get "/", HomeController, :index
    get "/healthz", HealthController, :show
  end

  pipeline :api do
    plug :accepts, ["json", "event-stream"]
  end

  scope "/api", JidoHiveServerWeb do
    pipe_through :api

    get "/connectors/:connector_id/connections", ConnectorController, :connections
    post "/connectors/:connector_id/installs", ConnectorController, :start_install
    get "/connectors/installs/:install_id", ConnectorController, :show_install
    post "/connectors/installs/:install_id/complete", ConnectorController, :complete_install
    get "/targets", TargetController, :index
    get "/policies", PoliciesController, :index
    get "/policies/*id", PoliciesController, :show
    post "/rooms", RoomController, :create
    get "/rooms/:id", RoomController, :show
    get "/rooms/:id/events", RoomEventsController, :index
    get "/rooms/:id/timeline", RoomTimelineController, :index
    get "/rooms/:id/context_objects", RoomContextController, :index
    get "/rooms/:id/context_objects/:context_id", RoomContextController, :show
    post "/rooms/:id/contributions", RoomContributionController, :create
    post "/rooms/:id/run_operations", RoomController, :start_run_operation
    get "/rooms/:id/run_operations/:operation_id", RoomController, :show_run_operation
    get "/rooms/:id/publication_plan", RoomController, :publication_plan
    get "/rooms/:id/publications", RoomController, :publication_runs
    post "/rooms/:id/publications", RoomController, :execute_publications
    post "/rooms/:id/first_slice", RoomController, :run_first_slice
  end

  scope "/", JidoHiveServerWeb do
    get "/*path", HomeController, :not_found
  end
end
