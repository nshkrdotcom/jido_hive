defmodule JidoHiveConsole.ModelTest do
  use ExUnit.Case, async: true

  alias JidoHiveConsole.Model

  test "new/1 exposes the multi-screen defaults" do
    model = Model.new(participant_id: "alice", api_base_url: "http://localhost:4000/api")

    assert model.active_screen == :lobby
    assert model.lobby_rooms == []
    assert model.pane_focus == :context
    assert model.publish_bindings == %{}
    assert model.wizard_fields == %{}
    assert model.wizard_targets_state == :idle
    assert model.wizard_policies_state == :idle
    assert model.status_line == "Ready"
    assert model.poll_interval_ms == 1_000
    assert model.help_visible == false
    assert model.help_seen == MapSet.new()
  end

  test "selection and relation mode helpers remain bounded" do
    snapshot = %{
      "context_objects" => [
        %{"context_id" => "ctx-1", "object_type" => "belief", "title" => "One"},
        %{"context_id" => "ctx-2", "object_type" => "question", "title" => "Two"}
      ]
    }

    model = Model.new(snapshot: snapshot)

    assert Model.move_selection(model, 10).selected_context_index == 1
    assert Model.move_selection(model, -10).selected_context_index == 0
    assert Model.set_relation_mode(model, :resolves).relation_mode == :resolves
  end

  test "apply_snapshot preserves contributions and operations" do
    model =
      Model.new(
        snapshot: %{
          "context_objects" => [],
          "contributions" => [%{"participant_id" => "alice", "summary" => "hello"}],
          "operations" => [%{"operation_id" => "room_submit-1", "status" => "completed"}]
        }
      )

    assert get_in(model.snapshot, ["contributions"]) == [
             %{"participant_id" => "alice", "summary" => "hello"}
           ]

    assert get_in(model.snapshot, ["operations"]) == [
             %{"operation_id" => "room_submit-1", "status" => "completed"}
           ]
  end

  test "dismiss_help marks the current screen as seen" do
    model = Model.new([]) |> Map.put(:active_screen, :room) |> Map.put(:help_visible, true)
    next = Model.dismiss_help(model)

    assert next.help_visible == false
    assert MapSet.member?(next.help_seen, :room)
  end

  test "help scroll resets on show and stays non-negative while scrolling" do
    model = Model.new([]) |> Map.put(:help_scroll, 4)

    shown = Model.show_help(model)
    assert shown.help_visible
    assert shown.help_scroll == 0

    assert Model.scroll_help(shown, 3).help_scroll == 3
    assert Model.scroll_help(shown, -10).help_scroll == 0
    assert Model.set_help_scroll(shown, -2).help_scroll == 0
    assert Model.scroll_help(shown, 99, 5).help_scroll == 5
    assert Model.set_help_scroll(shown, 99, 5).help_scroll == 5
  end
end
