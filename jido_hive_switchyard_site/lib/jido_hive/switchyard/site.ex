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
        resource_kinds: [:room, :participant, :assignment, :event],
        route_kind: :workspace,
        tui_component: JidoHive.Switchyard.TUI.RoomsComponent
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
      })
    ]
  end

  @impl true
  def resources(snapshot) when is_map(snapshot) do
    rooms = snapshot |> Map.get(:rooms, []) |> Enum.map(&room_resource/1)
    participants = snapshot |> Map.get(:participants, []) |> Enum.map(&participant_resource/1)
    assignments = snapshot |> Map.get(:assignments, []) |> Enum.map(&assignment_resource/1)
    events = snapshot |> Map.get(:events, []) |> Enum.map(&event_resource/1)

    rooms ++ participants ++ assignments ++ events
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
          "status: #{Map.get(room, :status, "unknown")}"
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
        "Inspect provenance"
      ]
    })
  end

  def detail(%Resource{kind: :participant} = resource, snapshot) do
    participant =
      snapshot
      |> Map.get(:participants, [])
      |> Enum.find(&(resource_id(&1) == resource.id))
      |> normalize_resource()

    metadata =
      participant
      |> Map.get(:meta, %{})
      |> Enum.map(fn {key, value} -> "#{key}: #{value}" end)

    ResourceDetail.new!(%{
      resource: resource,
      sections: [
        %{
          title: "Participant",
          lines:
            [
              "role: #{Map.get(participant, :role, "unknown")}",
              "kind: #{Map.get(participant, :kind, "unknown")}"
            ] ++ metadata
        }
      ],
      recommended_actions: []
    })
  end

  def detail(%Resource{kind: :assignment} = resource, snapshot) do
    assignment =
      snapshot
      |> Map.get(:assignments, [])
      |> Enum.find(&(resource_id(&1) == resource.id))
      |> normalize_resource()

    ResourceDetail.new!(%{
      resource: resource,
      sections: [
        %{
          title: "Assignment",
          lines: [
            "status: #{Map.get(assignment, :status, "unknown")}",
            "phase: #{Map.get(assignment, :phase, "unknown")}",
            "participant: #{Map.get(assignment, :participant_id, "unknown")}"
          ]
        }
      ],
      recommended_actions: []
    })
  end

  def detail(%Resource{kind: :event} = resource, snapshot) do
    event =
      snapshot
      |> Map.get(:events, [])
      |> Enum.find(&(resource_id(&1) == resource.id))
      |> normalize_resource()

    ResourceDetail.new!(%{
      resource: resource,
      sections: [
        %{
          title: "Event",
          lines: [
            "type: #{Map.get(event, :type, "unknown")}",
            "sequence: #{Map.get(event, :sequence, "unknown")}"
          ]
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
      tags: room_tags(room),
      capabilities: [:inspect, :run],
      summary: Map.get(room, :next_action) || Map.get(room, :brief)
    })
  end

  defp participant_resource(participant) do
    Resource.new!(%{
      site_id: @site_id,
      kind: :participant,
      id: resource_id(participant),
      title: Map.get(participant, :display_name) || resource_id(participant),
      subtitle: Map.get(participant, :role) || Map.get(participant, :kind),
      status: resource_status(Map.get(participant, :status)),
      capabilities: [:inspect],
      summary: Map.get(participant, :kind)
    })
  end

  defp assignment_resource(assignment) do
    Resource.new!(%{
      site_id: @site_id,
      kind: :assignment,
      id: resource_id(assignment),
      title: Map.get(assignment, :objective) || resource_id(assignment),
      subtitle: Map.get(assignment, :phase) || Map.get(assignment, :status),
      status: resource_status(Map.get(assignment, :status)),
      capabilities: [:inspect],
      summary: Map.get(assignment, :participant_id)
    })
  end

  defp event_resource(event) do
    Resource.new!(%{
      site_id: @site_id,
      kind: :event,
      id: resource_id(event),
      title: Map.get(event, :type) || resource_id(event),
      subtitle: "sequence #{Map.get(event, :sequence, "unknown")}",
      status: :ready,
      capabilities: [:inspect],
      summary: Map.get(event, :room_id)
    })
  end

  defp room_id(room), do: Map.get(room, :id) || Map.get(room, :room_id)
  defp resource_id(resource), do: Map.get(resource, :id) || Map.get(resource, :room_id)
  defp normalize_resource(resource) when is_map(resource), do: resource
  defp normalize_resource(_resource), do: %{}

  defp room_tags(room) do
    case Map.get(room, :status) do
      status when status in [:failed, "failed"] -> [:failed]
      status when status in [:closed, "closed"] -> [:closed]
      _other -> []
    end
  end

  defp resource_status(:ready), do: :ready
  defp resource_status(:queued), do: :queued
  defp resource_status(:running), do: :running
  defp resource_status(:failed), do: :failed
  defp resource_status("waiting"), do: :queued
  defp resource_status("active"), do: :running
  defp resource_status("completed"), do: :ready
  defp resource_status("closed"), do: :ready
  defp resource_status("running"), do: :running
  defp resource_status("failed"), do: :failed
  defp resource_status(_status), do: :unknown
end
