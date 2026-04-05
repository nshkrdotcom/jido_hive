defmodule JidoHiveServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JidoHiveServerWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:jido_hive_server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: JidoHiveServer.PubSub},
      {Jido.Signal.Bus, name: JidoHiveServer.SignalBus},
      JidoHiveServer.Repo,
      {Registry, keys: :unique, name: JidoHiveServer.Collaboration.Registry},
      {DynamicSupervisor,
       strategy: :one_for_one, name: JidoHiveServer.Collaboration.RoomSupervisor},
      JidoHiveServer.IntegrationsBootstrap,
      JidoHiveServer.RemoteExec,
      JidoHiveServerWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: JidoHiveServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JidoHiveServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
