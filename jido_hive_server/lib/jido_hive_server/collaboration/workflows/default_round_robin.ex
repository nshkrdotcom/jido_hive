defmodule JidoHiveServer.Collaboration.Workflows.DefaultRoundRobin do
  @moduledoc false

  @behaviour JidoHiveServer.Collaboration.Workflow

  alias JidoHiveServer.Collaboration.Referee

  @workflow_id "default.round_robin/v1"
  @stages [
    %{phase: "proposal", participant_role: "proposer"},
    %{phase: "critique", participant_role: "critic"},
    %{phase: "resolution", participant_role: "resolver"}
  ]

  @impl true
  def id, do: @workflow_id

  @impl true
  def load_defaults(config) when is_map(config), do: config

  @impl true
  def stages(_config), do: @stages

  @impl true
  def next_assignment(snapshot, available_target_ids) when is_map(snapshot) do
    Referee.next_assignment(snapshot, available_target_ids)
  end

  @impl true
  def status(snapshot) when is_map(snapshot), do: Referee.room_status(snapshot)
end
