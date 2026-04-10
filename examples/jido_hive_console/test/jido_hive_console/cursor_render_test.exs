defmodule JidoHiveConsole.CursorRenderTest do
  use ExUnit.Case, async: false

  alias ExRatatui
  alias ExRatatui.Widgets.{Textarea, TextInput}
  alias JidoHiveConsole.{App, Model, TestSupport}

  test "room view renders a multiline textarea widget with the current value" do
    ref = new_room_editor("hello\nworld")

    state =
      Model.new(
        room_id: "room-1",
        participant_id: "alice",
        authority_level: "binding",
        room_input_ref: ref,
        snapshot: %{
          "timeline" => [],
          "context_objects" => [],
          "status" => "running",
          "dispatch_state" => %{"completed_slots" => 0, "total_slots" => 2}
        }
      )
      |> Map.put(:active_screen, :room)
      |> Map.put(:input_buffer, "hello\nworld")

    rendered = App.view(state)

    assert Enum.any?(TestSupport.widgets(rendered, Textarea), fn
             %Textarea{state: ^ref, block: %{title: "Compose Steering Message"}} -> true
             _other -> false
           end)

    assert TestSupport.textarea_values(rendered) == ["hello\nworld"]
  end

  test "room view renders workflow and selected detail panes" do
    state =
      Model.new(
        room_id: "room-1",
        participant_id: "alice",
        authority_level: "binding",
        snapshot: %{
          "brief" => "Stabilize Redis auth",
          "timeline" => [],
          "context_objects" => [
            %{
              "context_id" => "ctx-1",
              "object_type" => "belief",
              "title" => "Redis timeout",
              "derived" => %{
                "duplicate_status" => "canonical",
                "duplicate_size" => 2,
                "duplicate_context_ids" => ["ctx-1", "ctx-2"],
                "canonical_context_id" => "ctx-1"
              }
            },
            %{
              "context_id" => "ctx-2",
              "object_type" => "belief",
              "title" => "Redis timeout",
              "derived" => %{
                "duplicate_status" => "duplicate",
                "duplicate_size" => 2,
                "duplicate_context_ids" => ["ctx-1", "ctx-2"],
                "canonical_context_id" => "ctx-1"
              }
            }
          ],
          "status" => "running",
          "workflow_summary" => %{
            "objective" => "Stabilize Redis auth",
            "stage" => "Resolve contradictions",
            "next_action" => "Review ctx-4 and submit a binding resolution",
            "blockers" => [%{"kind" => "contradiction", "count" => 1}],
            "publish_ready" => false,
            "publish_blockers" => ["Open contradictions remain"],
            "graph_counts" => %{
              "total" => 1,
              "decisions" => 0,
              "questions" => 0,
              "contradictions" => 1,
              "duplicate_groups" => 1,
              "duplicates" => 1,
              "stale" => 0
            },
            "focus_candidates" => [%{"kind" => "contradiction", "context_id" => "ctx-4"}]
          },
          "dispatch_state" => %{"completed_slots" => 1, "total_slots" => 2}
        }
      )
      |> Map.put(:active_screen, :room)

    rendered = App.view(state)
    text = rendered |> TestSupport.collect_text() |> Enum.join("\n")

    assert text =~ "Workflow"
    assert text =~ "Selected Detail"
    assert text =~ "Stage: Resolve contradictions"
    assert text =~ "Next action: Review ctx-4 and submit a binding resolution"
    assert text =~ "Redis timeout"
    assert text =~ "DUP:1"
  end

  test "conflict view renders a resolution text input widget with the current value" do
    ref = new_input("merge both")

    state =
      Model.new(authority_level: "binding", conflict_input_ref: ref)
      |> Map.put(:active_screen, :conflict)
      |> Map.put(:conflict_input_buf, "merge both")
      |> Map.put(:conflict_left, %{"context_id" => "left-1", "title" => "Left"})
      |> Map.put(:conflict_right, %{"context_id" => "right-1", "title" => "Right"})

    rendered = App.view(state)

    assert Enum.any?(TestSupport.widgets(rendered, TextInput), fn
             %TextInput{state: ^ref, block: %{title: "Resolution Draft (BINDING)"}} -> true
             _other -> false
           end)

    assert TestSupport.text_input_values(rendered) == ["merge both"]
  end

  test "wizard brief step renders a text input widget with the brief text" do
    ref = new_input("new room")

    state =
      Model.new(wizard_brief_input_ref: ref)
      |> Map.put(:active_screen, :wizard)
      |> Map.put(:wizard_step, 0)
      |> Map.put(:wizard_fields, %{"brief" => "new room"})

    rendered = App.view(state)

    assert Enum.any?(TestSupport.widgets(rendered, TextInput), fn
             %TextInput{state: ^ref, block: %{title: "Room Objective"}} -> true
             _other -> false
           end)

    assert TestSupport.text_input_values(rendered) == ["new room"]
  end

  test "wizard non-input steps do not render any text input widgets" do
    state =
      Model.new([])
      |> Map.put(:active_screen, :wizard)
      |> Map.put(:wizard_step, 1)
      |> Map.put(:wizard_policies_state, :ready)
      |> Map.put(:wizard_available_policies, [])

    assert TestSupport.widgets(App.view(state), TextInput) == []
  end

  defp new_input(value) do
    ref = ExRatatui.text_input_new()
    :ok = ExRatatui.text_input_set_value(ref, value)
    ref
  end

  defp new_room_editor(value) do
    ref = ExRatatui.textarea_new()
    :ok = ExRatatui.textarea_set_value(ref, value)
    ref
  end
end
