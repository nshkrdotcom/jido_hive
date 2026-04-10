defmodule JidoHiveConsole.InputKeyTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event
  alias JidoHiveConsole.{App, InputKey, Model}

  test "text_input_key normalizes shifted printable letters" do
    assert InputKey.text_input_key(%Event.Key{code: "d", modifiers: ["shift"]}) == {:ok, "D"}
    assert InputKey.text_input_key(%Event.Key{code: "!", modifiers: ["shift"]}) == {:ok, "!"}
    assert InputKey.text_input_key(%Event.Key{code: "up", modifiers: ["shift"]}) == :error
  end

  test "wizard step accepts shifted printable input" do
    state =
      Model.new([])
      |> Map.put(:active_screen, :wizard)
      |> Map.put(:wizard_step, 0)

    assert App.event_to_msg(%Event.Key{code: "d", modifiers: ["shift"]}, state) ==
             {:msg, {:wizard_input_key, "D"}}

    {next_state, []} = App.update({:wizard_input_key, "D"}, state)

    assert next_state.wizard_fields["brief"] == "D"
  end

  test "room screen accepts shifted printable input" do
    state =
      Model.new([])
      |> Map.put(:active_screen, :room)

    assert App.event_to_msg(%Event.Key{code: "j", modifiers: ["shift"]}, state) ==
             {:msg, {:room_input_key, "J"}}
  end

  test "conflict screen accepts shifted printable input" do
    state =
      Model.new([])
      |> Map.put(:active_screen, :conflict)

    assert App.event_to_msg(%Event.Key{code: "n", modifiers: ["shift"]}, state) ==
             {:msg, {:conflict_input_key, "N"}}
  end

  test "publish binding editor accepts shifted printable input" do
    state =
      Model.new([])
      |> Map.put(:active_screen, :publish)
      |> Map.put(:publish_plan, %{
        "publications" => [
          %{
            "channel" => "github",
            "required_bindings" => [%{"field" => "repo", "description" => "Repository"}]
          }
        ]
      })
      |> Map.put(:publish_cursor, 1)

    assert App.event_to_msg(%Event.Key{code: "n", modifiers: ["shift"]}, state) ==
             {:msg, {:publish_input_key, "N"}}
  end

  test "publish binding editor does not steal plain r for refresh" do
    state =
      Model.new([])
      |> Map.put(:active_screen, :publish)
      |> Map.put(:publish_plan, %{
        "publications" => [
          %{
            "channel" => "github",
            "required_bindings" => [%{"field" => "repo", "description" => "Repository"}]
          }
        ]
      })
      |> Map.put(:publish_cursor, 1)

    assert App.event_to_msg(%Event.Key{code: "r", modifiers: []}, state) ==
             {:msg, {:publish_input_key, "r"}}
  end
end
