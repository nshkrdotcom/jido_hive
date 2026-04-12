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
    post "/targets", TargetController, :create
    delete "/targets/:target_id", TargetController, :delete
    get "/policies", PoliciesController, :index
    get "/policies/*id", PoliciesController, :show
    get "/rooms", RoomController, :index
    post "/rooms", RoomController, :create
    get "/rooms/:id", RoomController, :show
    patch "/rooms/:id", RoomController, :patch
    delete "/rooms/:id", RoomController, :delete

    post "/rooms/:id/participants", RoomParticipantsController, :create
    get "/rooms/:id/participants", RoomParticipantsController, :index
    delete "/rooms/:id/participants/:participant_id", RoomParticipantsController, :delete

    post "/rooms/:id/contributions", RoomContributionsController, :create
    get "/rooms/:id/contributions", RoomContributionsController, :index

    get "/rooms/:id/assignments", RoomAssignmentsController, :index
    patch "/rooms/:id/assignments/:assignment_id", RoomAssignmentsController, :update

    get "/rooms/:id/events", RoomEventsController, :index

    post "/rooms/:id/runs", RoomRunsController, :create
    get "/rooms/:id/runs/:run_id", RoomRunsController, :show
    delete "/rooms/:id/runs/:run_id", RoomRunsController, :delete
  end

  scope "/", JidoHiveServerWeb do
    get "/*path", HomeController, :not_found
  end
end
