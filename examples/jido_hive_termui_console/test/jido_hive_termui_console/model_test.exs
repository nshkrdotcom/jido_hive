defmodule JidoHiveTermuiConsole.ModelTest do
  use ExUnit.Case, async: true

  alias JidoHiveTermuiConsole.Model

  defmodule EmbeddedStub do
    def snapshot(_pid) do
      %{
        timeline: [%{"body" => "alice: hello"}],
        context_objects: [
          %{"context_id" => "ctx-1", "object_type" => "hypothesis", "title" => "Redis timeout"},
          %{"context_id" => "ctx-2", "object_type" => "decision_candidate", "title" => "Rollback"}
        ]
      }
    end
  end

  test "applies snapshots and clamps selection" do
    model =
      Model.new(
        embedded: self(),
        embedded_module: EmbeddedStub,
        room_id: "room-1",
        snapshot: EmbeddedStub.snapshot(self())
      )

    assert model.selected_context_index == 0
    assert Model.move_selection(model, 10).selected_context_index == 1
    assert Model.move_selection(model, -10).selected_context_index == 0
  end

  test "tracks input edits" do
    model =
      Model.new(
        embedded: self(),
        embedded_module: EmbeddedStub,
        room_id: "room-1",
        snapshot: EmbeddedStub.snapshot(self())
      )

    model = model |> Model.append_input("h") |> Model.append_input("i") |> Model.backspace()
    assert model.input_buffer == "h"
    assert Model.clear_input(model).input_buffer == ""
  end
end
