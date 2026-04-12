defmodule JidoHive.Switchyard.SiteTest do
  use ExUnit.Case, async: true

  alias JidoHive.Switchyard.Site
  alias Switchyard.Contracts.Resource

  @snapshot %{
    rooms: [
      %{
        id: "room-1",
        title: "Stabilize auth path",
        stage: "Resolve contradictions",
        status: "active",
        next_action: "Review ctx-2"
      }
    ],
    participants: [
      %{id: "participant-1", display_name: "Alice", role: "operator", kind: "human"}
    ],
    assignments: [
      %{
        id: "assignment-1",
        objective: "Review the current contradictions",
        phase: "analysis",
        status: "active",
        participant_id: "participant-1"
      }
    ],
    events: [
      %{id: "event-1", room_id: "room-1", type: "room.created", sequence: 1}
    ]
  }

  test "declares the jido hive site and canonical app kinds" do
    assert Site.site_definition().id == "jido-hive"

    assert [%{id: "jido-hive.rooms", resource_kinds: [:room, :participant, :assignment, :event]}] =
             Site.apps()
  end

  test "maps canonical room resources into switchyard resources" do
    resources = Site.resources(@snapshot)

    assert Enum.any?(resources, &(&1.kind == :room and &1.id == "room-1"))
    assert Enum.any?(resources, &(&1.kind == :participant and &1.id == "participant-1"))
    assert Enum.any?(resources, &(&1.kind == :assignment and &1.id == "assignment-1"))
    assert Enum.any?(resources, &(&1.kind == :event and &1.id == "event-1"))
    refute Enum.any?(resources, &(&1.kind == :publication))
  end

  test "builds resource detail from room workflow state" do
    room =
      Resource.new!(%{
        site_id: "jido-hive",
        kind: :room,
        id: "room-1",
        title: "Stabilize auth path"
      })

    detail = Site.detail(room, @snapshot)

    assert Enum.any?(detail.sections, fn section ->
             section.title == "Workflow" and
               Enum.any?(section.lines, &String.contains?(&1, "Resolve contradictions"))
           end)

    refute "Publish room output" in detail.recommended_actions
  end
end
