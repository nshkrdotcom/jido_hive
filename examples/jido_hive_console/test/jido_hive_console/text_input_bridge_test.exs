defmodule JidoHiveConsole.TextInputBridgeTest do
  use ExUnit.Case, async: false

  alias ExRatatui
  alias JidoHiveConsole.{Model, TextInputBridge}

  test "ensure_refs allocates missing text input references" do
    state = TextInputBridge.ensure_refs(Model.new([]))

    assert is_reference(state.room_input_ref)
    assert is_reference(state.conflict_input_ref)
    assert is_reference(state.wizard_brief_input_ref)
    assert is_reference(state.publish_input_ref)
  end

  test "sync mirrors model draft values into the backing refs" do
    state =
      Model.new([])
      |> TextInputBridge.ensure_refs()
      |> Map.put(:input_buffer, "room")
      |> Map.put(:conflict_input_buf, "conflict")
      |> Map.put(:wizard_fields, %{"brief" => "wizard"})
      |> Map.put(:publish_plan, %{
        "publications" => [
          %{"channel" => "github", "required_bindings" => [%{"field" => "repo"}]}
        ]
      })
      |> Map.put(:publish_cursor, 1)
      |> Map.put(:publish_bindings, %{"github" => %{"repo" => "repo-name"}})

    synced = TextInputBridge.sync(state)

    assert ExRatatui.textarea_get_value(synced.room_input_ref) == "room"
    assert ExRatatui.text_input_get_value(synced.conflict_input_ref) == "conflict"
    assert ExRatatui.text_input_get_value(synced.wizard_brief_input_ref) == "wizard"
    assert ExRatatui.text_input_get_value(synced.publish_input_ref) == "repo-name"
  end

  test "handle_room_key falls back to pure elixir editing without a ref" do
    state = Model.new([]) |> Map.put(:input_buffer, "hi")

    next_state = TextInputBridge.handle_room_key(state, "!")

    assert next_state.input_buffer == "hi!"
  end

  test "handle_room_key keeps the model value in sync with the ref" do
    ref = ExRatatui.textarea_new()
    :ok = ExRatatui.textarea_set_value(ref, "hi")
    :ok = ExRatatui.textarea_handle_key(ref, "end", [])

    state = Model.new(room_input_ref: ref) |> Map.put(:input_buffer, "hi")

    next_state = TextInputBridge.handle_room_key(state, "!")

    assert next_state.input_buffer == "hi!"
    assert ExRatatui.textarea_get_value(ref) == "hi!"
  end

  test "handle_room_key can insert a newline for the multiline room editor" do
    ref = ExRatatui.textarea_new()
    :ok = ExRatatui.textarea_set_value(ref, "hi")
    :ok = ExRatatui.textarea_handle_key(ref, "end", [])

    state = Model.new(room_input_ref: ref) |> Map.put(:input_buffer, "hi")

    next_state = TextInputBridge.handle_room_key(state, "enter")

    assert next_state.input_buffer == "hi\n"
    assert ExRatatui.textarea_get_value(ref) == "hi\n"
  end

  test "handle_publish_key updates the focused binding through the shared helper" do
    ref = ExRatatui.text_input_new()
    :ok = ExRatatui.text_input_set_value(ref, "repo")

    state =
      Model.new(publish_input_ref: ref)
      |> Map.put(:publish_plan, %{
        "publications" => [
          %{"channel" => "github", "required_bindings" => [%{"field" => "repo"}]}
        ]
      })
      |> Map.put(:publish_cursor, 1)
      |> Map.put(:publish_bindings, %{"github" => %{"repo" => "repo"}})

    next_state = TextInputBridge.handle_publish_key(state, "!")

    assert get_in(next_state.publish_bindings, ["github", "repo"]) == "repo!"
    assert ExRatatui.text_input_get_value(ref) == "repo!"
  end
end
