defmodule JidoHiveServer.Collaboration.Schema.ContributionTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.Schema.Contribution

  test "builds a canonical contribution" do
    assert {:ok, contribution} =
             Contribution.new(%{
               id: "ctrb-1",
               room_id: "room-1",
               assignment_id: "asg-1",
               participant_id: "participant-1",
               kind: "reasoning",
               payload: %{"summary" => "Produced a reasoning contribution."},
               meta: %{"trace" => %{"provider" => "codex"}}
             })

    assert contribution.id == "ctrb-1"
    assert contribution.assignment_id == "asg-1"
    assert contribution.kind == "reasoning"
    assert contribution.payload["summary"] == "Produced a reasoning contribution."
    assert contribution.meta["trace"]["provider"] == "codex"
  end

  test "requires canonical kind field" do
    assert {:error, {:missing_field, "kind"}} =
             Contribution.new(%{
               id: "ctrb-1",
               room_id: "room-1",
               participant_id: "participant-1"
             })
  end
end
