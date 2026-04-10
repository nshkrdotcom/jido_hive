defmodule JidoHiveConsole.HelpGuideTest do
  use ExUnit.Case, async: true

  alias JidoHiveConsole.{HelpGuide, Model}

  test "room help includes current state and workflow guidance" do
    state =
      Model.new(
        room_id: "room-1",
        snapshot: %{
          "status" => "running",
          "timeline" => [],
          "context_objects" => [
            %{"context_id" => "ctx-1", "object_type" => "belief", "title" => "Root hypothesis"}
          ]
        }
      )
      |> Map.put(:active_screen, :room)
      |> Map.put(:relation_mode, :supports)
      |> Map.put(:input_buffer, "draft")

    text = state |> HelpGuide.lines() |> Enum.join("\n")

    assert HelpGuide.title(state) == "Room Help"
    assert text =~ "CURRENT STATE"
    assert text =~ "Room: room-1."
    assert text =~ "Selected context: ctx-1."
    assert text =~ "Relation mode: supports."
    assert text =~ "WORKFLOW"
  end

  test "publish help explains focus-sensitive binding and auth behavior" do
    state =
      Model.new([])
      |> Map.put(:active_screen, :publish)
      |> Map.put(:publish_plan, %{
        "publications" => [
          %{
            "channel" => "github",
            "required_bindings" => [%{"field" => "repo", "description" => "Owner/repo"}]
          }
        ]
      })
      |> Map.put(:publish_selected, ["github"])
      |> Map.put(:publish_cursor, 1)
      |> Map.put(:publish_auth_state, %{
        "github" => %{status: :cached, connection_id: "connection-1", source: :server}
      })

    text = state |> HelpGuide.lines() |> Enum.join("\n")

    assert HelpGuide.title(state) == "Publish Help"
    assert text =~ "Focused item: binding github.repo."
    assert text =~ "The letter r is treated as text while a binding field is focused."
    assert text =~ "Auth summary: github=connected."
  end

  test "wizard help describes the active step and pending create state" do
    state =
      Model.new([])
      |> Map.put(:active_screen, :wizard)
      |> Map.put(:wizard_step, 4)
      |> Map.put(:wizard_fields, %{
        "brief" => "Refine the room operator workflow",
        "participants" => [%{"participant_id" => "worker-01"}]
      })
      |> Map.put(:pending_room_create, %{room_id: "room-123"})

    text = state |> HelpGuide.lines() |> Enum.join("\n")

    assert HelpGuide.title(state) == "Wizard Help"
    assert text =~ "Step: 4/4 — Confirm."
    assert text =~ "Selected workers: 1."
    assert text =~ "Pending create: room-123."
    assert text =~ "Room creation is already running in the background."
  end
end
