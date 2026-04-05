defmodule JidoHiveServer.Collaboration.Workflows.ChainOfResponsibility do
  @moduledoc false

  @behaviour JidoHiveServer.Collaboration.Workflow

  alias JidoHiveServer.Collaboration.Referee

  @workflow_id "chain_of_responsibility/v1"

  @impl true
  def id, do: @workflow_id

  @impl true
  def load_defaults(config) when is_map(config) do
    Map.put_new(config, "phases", default_phases())
  end

  @impl true
  def stages(config) when is_map(config) do
    config
    |> load_defaults()
    |> Map.fetch!("phases")
    |> Enum.map(fn phase ->
      %{
        phase: phase["phase"] || phase[:phase],
        participant_role: phase["participant_role"] || phase[:participant_role]
      }
    end)
  end

  @impl true
  def next_assignment(snapshot, available_target_ids) when is_map(snapshot) do
    Referee.next_assignment(snapshot, available_target_ids)
  end

  @impl true
  def status(snapshot) when is_map(snapshot), do: Referee.room_status(snapshot)

  defp default_phases do
    [
      %{"phase" => "draft", "participant_role" => "author"},
      %{"phase" => "review", "participant_role" => "reviewer"},
      %{"phase" => "finalize", "participant_role" => "finalizer"}
    ]
  end
end
