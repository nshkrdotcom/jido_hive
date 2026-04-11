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
        status: :running,
        publish_ready: false,
        next_action: "Review ctx-2"
      }
    ],
    publications: [
      %{id: "pub-1", title: "GitHub summary", status: "draft", target: "github"}
    ]
  }

  test "declares the jido hive site and apps" do
    assert Site.site_definition().id == "jido-hive"

    assert Enum.map(Site.apps(), & &1.id) == [
             "jido-hive.rooms",
             "jido-hive.publications"
           ]
  end

  test "maps workflow rooms into switchyard resources" do
    resources = Site.resources(@snapshot)

    assert Enum.any?(resources, &(&1.kind == :room and &1.id == "room-1"))
    assert Enum.any?(resources, &(&1.kind == :publication and &1.id == "pub-1"))
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
  end
end
