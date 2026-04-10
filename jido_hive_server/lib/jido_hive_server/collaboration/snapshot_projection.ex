defmodule JidoHiveServer.Collaboration.SnapshotProjection do
  @moduledoc false

  alias JidoHiveServer.Collaboration.{
    ContextDeduper,
    ContextGraph,
    ContextManager,
    WorkflowSummary
  }

  @spec project(map()) :: map()
  def project(snapshot) when is_map(snapshot) do
    snapshot
    |> ensure_context_defaults()
    |> ContextGraph.attach()
    |> then(fn projected ->
      annotations =
        projected
        |> rebuild_annotations()

      projected =
        projected
        |> Map.put(:context_annotations, annotations)

      projected
      |> Map.put(:workflow_summary, WorkflowSummary.build(projected))
    end)
  end

  @spec strip_derived(map()) :: map()
  def strip_derived(snapshot) when is_map(snapshot) do
    snapshot
    |> Map.drop([:context_graph, :context_annotations, :workflow_summary])
    |> Map.put(:context_config, normalize_context_config(Map.get(snapshot, :context_config, %{})))
  end

  defp ensure_context_defaults(snapshot) do
    snapshot
    |> Map.put_new(:context_config, %{participant_scopes: %{}})
    |> Map.put_new(:context_annotations, %{})
  end

  defp rebuild_annotations(projected) do
    projected
    |> ContextManager.rebuild_annotations()
    |> merge_annotations(ContextDeduper.rebuild_annotations(projected))
  end

  defp merge_annotations(left, right) do
    Map.merge(left, right, fn _context_id, left_annotation, right_annotation ->
      Map.merge(left_annotation, right_annotation)
    end)
  end

  defp normalize_context_config(%{} = context_config) do
    participant_scopes =
      context_config
      |> Map.get(:participant_scopes, Map.get(context_config, "participant_scopes", %{}))
      |> Map.new(fn {participant_id, scope} ->
        {participant_id, normalize_scope(scope)}
      end)

    %{participant_scopes: participant_scopes}
  end

  defp normalize_context_config(_context_config), do: %{participant_scopes: %{}}

  defp normalize_scope(%{} = scope) do
    %{
      writable_types:
        normalize_dimension(Map.get(scope, :writable_types) || Map.get(scope, "writable_types")),
      writable_node_ids:
        normalize_dimension(
          Map.get(scope, :writable_node_ids) || Map.get(scope, "writable_node_ids")
        ),
      reference_hop_limit:
        Map.get(scope, :reference_hop_limit) || Map.get(scope, "reference_hop_limit") || 2
    }
  end

  defp normalize_scope(_scope) do
    %{
      writable_types: :all,
      writable_node_ids: :all,
      reference_hop_limit: 2
    }
  end

  defp normalize_dimension(:all), do: :all
  defp normalize_dimension("all"), do: :all

  defp normalize_dimension(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp normalize_dimension(_values), do: :all
end
