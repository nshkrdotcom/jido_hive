defmodule JidoHiveServer.Collaboration.Schema.ContributionTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.Schema.Contribution

  test "builds a contribution with canonical defaults" do
    assert {:ok, contribution} =
             Contribution.new(%{
               room_id: "room-1",
               assignment_id: "asn-1",
               participant_id: "worker-01",
               participant_role: "analyst",
               contribution_type: "reasoning",
               authority_level: "advisory",
               summary: "Produced a reasoning contribution."
             })

    assert contribution.status == "completed"
    assert contribution.context_objects == []
    assert contribution.schema_version == "jido_hive/contribution.submit.v1"
  end
end
