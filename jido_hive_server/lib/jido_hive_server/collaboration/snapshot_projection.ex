defmodule JidoHiveServer.Collaboration.SnapshotProjection do
  @moduledoc false

  alias JidoHiveContextGraph.Projector

  @spec project(map()) :: map()
  def project(snapshot) when is_map(snapshot) do
    Projector.project(snapshot)
  end

  @spec strip_derived(map()) :: map()
  def strip_derived(snapshot) when is_map(snapshot) do
    snapshot
    |> Map.drop([:context_graph, :context_annotations, :workflow_summary, :context_objects])
  end
end
