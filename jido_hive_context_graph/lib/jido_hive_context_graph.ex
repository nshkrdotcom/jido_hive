defmodule JidoHiveContextGraph do
  @moduledoc """
  External context-graph and workflow projections over generalized Jido Hive room state.
  """

  alias JidoHiveContextGraph.{ContextView, Projector, WorkflowSummary}

  @spec project(map()) :: map()
  def project(snapshot) when is_map(snapshot), do: Projector.project(snapshot)

  @spec build_context_view(map(), map(), map()) :: map()
  def build_context_view(
        snapshot,
        participant,
        task_context \\ %{mode: :human_pane, anchor_context_id: nil}
      )
      when is_map(snapshot) and is_map(participant) and is_map(task_context) do
    snapshot
    |> project()
    |> ContextView.build(participant, task_context)
  end

  @spec workflow_summary(map()) :: map()
  def workflow_summary(snapshot) when is_map(snapshot) do
    projected = project(snapshot)

    Map.get(projected, :workflow_summary) || Map.get(projected, "workflow_summary") ||
      WorkflowSummary.build(projected)
  end
end
