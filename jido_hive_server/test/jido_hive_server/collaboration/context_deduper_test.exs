defmodule JidoHiveServer.Collaboration.ContextDeduperTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.ContextDeduper

  test "rebuild_annotations marks canonical and duplicate objects in a stable group" do
    room = %{
      context_objects: [
        context_object("ctx-1", "belief", "Shared state", "The server owns room truth.",
          inserted_at: ~U[2026-04-09 10:00:00Z]
        ),
        context_object("ctx-2", "belief", "Shared state", "The server owns room truth.",
          inserted_at: ~U[2026-04-09 10:05:00Z]
        ),
        context_object("ctx-3", "belief", "Other state", "Different body.",
          inserted_at: ~U[2026-04-09 10:10:00Z]
        )
      ]
    }

    annotations = ContextDeduper.rebuild_annotations(room)

    assert annotations["ctx-1"] == %{
             duplicate_group_id: annotations["ctx-2"].duplicate_group_id,
             canonical_context_id: "ctx-1",
             duplicate_context_ids: ["ctx-1", "ctx-2"],
             duplicate_rank: 0,
             duplicate_size: 2,
             duplicate_status: "canonical"
           }

    assert annotations["ctx-2"] == %{
             duplicate_group_id: annotations["ctx-1"].duplicate_group_id,
             canonical_context_id: "ctx-1",
             duplicate_context_ids: ["ctx-1", "ctx-2"],
             duplicate_rank: 1,
             duplicate_size: 2,
             duplicate_status: "duplicate"
           }

    refute Map.has_key?(annotations, "ctx-3")
  end

  test "canonical_context_objects keeps only canonical items from duplicate groups" do
    room = %{
      context_objects: [
        context_object("ctx-1", "question", "Need clarification", "What is the target SLA?",
          inserted_at: ~U[2026-04-09 10:00:00Z]
        ),
        context_object("ctx-2", "question", "Need clarification", "What is the target SLA?",
          inserted_at: ~U[2026-04-09 10:01:00Z]
        ),
        context_object("ctx-3", "decision", "Proceed", "Proceed with the rollout.",
          inserted_at: ~U[2026-04-09 10:02:00Z]
        )
      ]
    }

    assert Enum.map(ContextDeduper.canonical_context_objects(room), & &1.context_id) == [
             "ctx-1",
             "ctx-3"
           ]
  end

  defp context_object(context_id, object_type, title, body, attrs) do
    %{
      context_id: context_id,
      object_type: object_type,
      title: title,
      body: body,
      data: %{},
      relations: Keyword.get(attrs, :relations, []),
      inserted_at: Keyword.get(attrs, :inserted_at, ~U[2026-04-09 10:00:00Z])
    }
  end
end
