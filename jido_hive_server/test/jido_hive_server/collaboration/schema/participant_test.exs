defmodule JidoHiveServer.Collaboration.Schema.ParticipantTest do
  use ExUnit.Case, async: true

  alias JidoHiveServer.Collaboration.Schema.Participant

  test "builds a runtime participant with defaults" do
    assert {:ok, participant} =
             Participant.new(%{
               participant_id: "worker-01",
               participant_role: "analyst",
               target_id: "target-worker-01",
               capability_id: "codex.exec.session"
             })

    assert participant.participant_kind == "runtime"
    assert participant.authority_level == "advisory"
    assert participant.target_id == "target-worker-01"
  end
end
