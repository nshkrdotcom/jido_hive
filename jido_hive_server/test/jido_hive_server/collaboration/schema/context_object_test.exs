defmodule JidoHiveServer.Collaboration.Schema.ContextObjectTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.Schema.ContextObject

  test "builds a context object from a contribution draft" do
    assert {:ok, context_object} =
             ContextObject.from_draft(
               %{
                 "object_type" => "belief",
                 "title" => "Room-scoped belief",
                 "body" => "The server should own shared room state.",
                 "relations" => [%{"relation" => "derives_from", "target_id" => "ctx-0"}]
               },
               %{
                 context_id: "ctx-1",
                 authored_by: %{
                   participant_id: "worker-01",
                   participant_role: "analyst",
                   target_id: "target-worker-01",
                   capability_id: "workspace.exec.session"
                 },
                 provenance: %{
                   contribution_id: "contrib-1",
                   assignment_id: "asn-1",
                   consumed_context_ids: ["ctx-0"],
                   source_event_ids: ["evt-1"],
                   authority_level: "advisory",
                   contribution_type: "reasoning"
                 },
                 inserted_at: DateTime.utc_now()
               }
             )

    assert context_object.object_type == "belief"
    assert context_object.scope.read == ["room"]
    assert context_object.scope.write == ["author"]
    assert context_object.uncertainty.status == "provisional"
  end
end
