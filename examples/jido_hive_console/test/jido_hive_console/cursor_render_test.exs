defmodule JidoHiveConsole.CursorRenderTest do
  use ExUnit.Case, async: false

  alias ExRatatui
  alias ExRatatui.Widgets.TextInput
  alias JidoHiveConsole.{App, Model, TestSupport}

  test "room view renders a draft text input widget with the current value" do
    ref = new_input("hello")

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
      |> Map.put(:input_buffer, "hello")

    rendered = App.view(state)

    assert Enum.any?(TestSupport.widgets(rendered, TextInput), fn
             %TextInput{state: ^ref, block: %{title: "Draft"}} -> true
             _other -> false
           end)

    assert TestSupport.text_input_values(rendered) == ["hello"]
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
             %TextInput{state: ^ref, block: %{title: "Room Brief"}} -> true
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
end
