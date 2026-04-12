defmodule JidoHiveContextGraph.ProjectorTest do
  use ExUnit.Case, async: true

  alias JidoHiveContextGraph.{ContributionValidator, Projector}

  test "keeps contribution-derived context ids stable across repeated projections" do
    snapshot = %{
      id: "room-1",
      name: "Design a substrate.",
      status: "waiting",
      contributions: [
        %{
          "id" => "contrib-1",
          "participant_id" => "worker-01",
          "payload" => %{
            "context_objects" => [
              %{"object_type" => "belief", "title" => "Shared state"}
            ]
          }
        }
      ]
    }

    first = Projector.project(snapshot)
    second = Projector.project(first)

    assert Enum.map(first.context_objects, & &1.context_id) == ["ctx-1"]
    assert Enum.map(second.context_objects, & &1.context_id) == ["ctx-1"]
    assert first.next_context_seq == 2
    assert second.next_context_seq == 2
  end

  test "preserves explicit workflow summaries when contributions are absent" do
    snapshot = %{
      id: "room-1",
      name: "Stabilize the auth path",
      workflow_summary: %{
        "stage" => "Resolve contradictions",
        "next_action" => "Review ctx-2",
        "objective" => "Stabilize the auth path"
      },
      context_objects: [
        %{"context_id" => "ctx-1", "object_type" => "belief", "title" => "Redis timeout"}
      ]
    }

    projected = Projector.project(snapshot)

    assert projected.workflow_summary == %{
             "stage" => "Resolve contradictions",
             "next_action" => "Review ctx-2",
             "objective" => "Stabilize the auth path"
           }
  end

  test "validator enforces participant scope from legacy context_config" do
    room = %{
      id: "room-1",
      context_config: %{
        participant_scopes: %{
          "worker-01" => %{
            writable_types: ["note"],
            writable_node_ids: :all,
            reference_hop_limit: 2
          }
        }
      },
      participants: [%{"id" => "worker-01", "kind" => "agent", "meta" => %{"role" => "worker"}}]
    }

    contribution = %{
      "participant_id" => "worker-01",
      "payload" => %{
        "context_objects" => [
          %{"object_type" => "decision", "title" => "Do not allow"}
        ]
      }
    }

    assert {:error, {:scope_violation, %{kind: :drafted_object_type, object_type: "decision"}}} =
             ContributionValidator.validate(contribution, room)
  end
end
