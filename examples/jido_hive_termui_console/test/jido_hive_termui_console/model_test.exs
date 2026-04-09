defmodule JidoHiveTermuiConsole.ModelTest do
  use ExUnit.Case, async: true

  alias JidoHiveTermuiConsole.Model

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

  test "dismiss_help marks the current screen as seen" do
    model = Model.new([]) |> Map.put(:active_screen, :room) |> Map.put(:help_visible, true)
    next = Model.dismiss_help(model)

    assert next.help_visible == false
    assert MapSet.member?(next.help_seen, :room)
  end
end
