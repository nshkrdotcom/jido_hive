defmodule JidoHive.Switchyard.Site do
  @moduledoc """
  Jido Hive site mapping over generic Switchyard contracts.
  """

  @behaviour Switchyard.Contracts.SiteProvider

  alias Switchyard.Contracts.{Action, AppDescriptor, Resource, ResourceDetail, SiteDescriptor}

  @site_id "jido-hive"

  @impl true
  def site_definition do
    SiteDescriptor.new!(%{
      id: @site_id,
      title: "Jido Hive",
      provider: __MODULE__,
      kind: :remote,
      environment: "default",
      capabilities: [:apps, :actions, :resources]
    })
  end

  @impl true
  def apps do
    [
      AppDescriptor.new!(%{
        id: "jido-hive.rooms",
        site_id: @site_id,
        title: "Rooms",
        provider: __MODULE__,
        resource_kinds: [:room],
        route_kind: :workspace
      }),
      AppDescriptor.new!(%{
        id: "jido-hive.publications",
        site_id: @site_id,
        title: "Publications",
        provider: __MODULE__,
        resource_kinds: [:publication],
        route_kind: :list_detail
      })
    ]
  end

  @impl true
  def actions do
    [
      Action.new!(%{
        id: "jido-hive.room.run",
        title: "Run room",
        scope: {:site, @site_id},
        provider: __MODULE__
      }),
      Action.new!(%{
        id: "jido-hive.room.submit",
        title: "Submit steering message",
        scope: {:resource, :room},
        provider: __MODULE__
      }),
      Action.new!(%{
        id: "jido-hive.room.provenance",
        title: "Inspect provenance",
        scope: {:resource, :room},
        provider: __MODULE__
      }),
      Action.new!(%{
        id: "jido-hive.room.publish",
        title: "Publish room output",
        scope: {:resource, :room},
        provider: __MODULE__,
        confirmation: :if_destructive
      })
    ]
  end

  @impl true
  def resources(snapshot) when is_map(snapshot) do
    rooms = snapshot |> Map.get(:rooms, []) |> Enum.map(&room_resource/1)
    publications = snapshot |> Map.get(:publications, []) |> Enum.map(&publication_resource/1)

    rooms ++ publications
  end

  @impl true
  def detail(%Resource{kind: :room} = resource, snapshot) do
    room = snapshot |> Map.get(:rooms, []) |> Enum.find(&(room_id(&1) == resource.id))

    workflow_lines =
      if is_map(room) and Map.has_key?(room, :control_plane) do
        control_plane = room.control_plane

        [
          "objective: #{control_plane.objective}",
          "stage: #{control_plane.stage}",
          "next: #{control_plane.next_action}",
          "why: #{control_plane.reason}"
        ]
      else
        [
          "stage: #{Map.get(room, :stage) || Map.get(room, :status, "unknown")}",
          "next: #{Map.get(room, :next_action) || Map.get(room, :brief, "Open the room workspace")}",
          "publish ready: #{Map.get(room, :publish_ready, false)}"
        ]
      end

    ResourceDetail.new!(%{
      resource: resource,
      sections: [
        %{title: "Workflow", lines: workflow_lines}
      ],
      recommended_actions: [
        "Run room",
        "Submit steering message",
        "Inspect provenance",
        "Publish room output"
      ]
    })
  end

  def detail(%Resource{kind: :publication} = resource, snapshot) do
    publication = snapshot |> Map.get(:publications, []) |> Enum.find(&(&1.id == resource.id))

    ResourceDetail.new!(%{
      resource: resource,
      sections: [
        %{
          title: "Publication",
          lines: ["status: #{publication.status}", "target: #{publication.target}"]
        }
      ],
      recommended_actions: []
    })
  end

  defp room_resource(room) do
    Resource.new!(%{
      site_id: @site_id,
      kind: :room,
      id: room_id(room),
      title: Map.get(room, :title) || Map.get(room, :brief) || room_id(room),
      subtitle: Map.get(room, :stage) || Map.get(room, :status),
      status: resource_status(Map.get(room, :status)),
      tags:
        if(Map.get(room, :publish_ready) || Map.get(room, :status) == "publication_ready",
          do: [:publish_ready],
          else: [:blocked]
        ),
      capabilities: [:inspect, :run, :publish],
      summary: Map.get(room, :next_action) || Map.get(room, :brief)
    })
  end

  defp publication_resource(publication) do
    Resource.new!(%{
      site_id: @site_id,
      kind: :publication,
      id: publication.id,
      title: publication.title,
      subtitle: publication.status,
      status: resource_status(publication.status),
      capabilities: [:inspect],
      summary: publication.target
    })
  end

  defp room_id(room), do: Map.get(room, :id) || Map.get(room, :room_id)

  defp resource_status(:ready), do: :ready
  defp resource_status(:queued), do: :queued
  defp resource_status(:running), do: :running
  defp resource_status(:failed), do: :failed
  defp resource_status("publication_ready"), do: :ready
  defp resource_status("running"), do: :running
  defp resource_status("failed"), do: :failed
  defp resource_status(_status), do: :unknown
end
