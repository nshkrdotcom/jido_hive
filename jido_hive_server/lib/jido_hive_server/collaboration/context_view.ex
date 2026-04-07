defmodule JidoHiveServer.Collaboration.ContextView do
  @moduledoc false

  alias JidoHiveServer.Collaboration.ContextManager

  @spec build(map(), map()) :: map()
  def build(snapshot, participant),
    do: build(snapshot, participant, %{mode: :human_pane, anchor_context_id: nil})

  @spec build(map(), map(), map()) :: map()
  def build(snapshot, participant, task_context)
      when is_map(snapshot) and is_map(participant) and is_map(task_context) do
    %{
      brief: Map.get(snapshot, :brief),
      rules: Map.get(snapshot, :rules, []),
      status: Map.get(snapshot, :status, "idle"),
      context_objects:
        ContextManager.build_view(participant, task_context, snapshot)
        |> Enum.map(&normalize_context_object/1),
      recent_contributions:
        Map.get(snapshot, :contributions, [])
        |> Enum.take(-5)
        |> Enum.map(&normalize_contribution/1)
    }
  end

  defp normalize_context_object(context_object) do
    %{
      context_id: Map.get(context_object, :context_id),
      object_type: Map.get(context_object, :object_type),
      title: Map.get(context_object, :title),
      body: Map.get(context_object, :body),
      data: Map.get(context_object, :data, %{}),
      authored_by: Map.get(context_object, :authored_by, %{}),
      provenance: Map.get(context_object, :provenance, %{}),
      scope: Map.get(context_object, :scope, %{}),
      uncertainty: Map.get(context_object, :uncertainty, %{}),
      relations: Map.get(context_object, :relations, []),
      derived: Map.get(context_object, :derived, %{})
    }
  end

  defp normalize_contribution(contribution) do
    %{
      contribution_id: Map.get(contribution, :contribution_id),
      participant_id: Map.get(contribution, :participant_id),
      participant_role: Map.get(contribution, :participant_role),
      contribution_type: Map.get(contribution, :contribution_type),
      summary: Map.get(contribution, :summary),
      authority_level: Map.get(contribution, :authority_level),
      status: Map.get(contribution, :status)
    }
  end
end
