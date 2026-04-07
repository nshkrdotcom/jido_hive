defmodule JidoHiveServerWeb.RelayChannelTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias JidoHiveServer.Collaboration
  alias JidoHiveServerWeb.RelayChannel

  test "returns an error reply instead of crashing when contribution acceptance fails" do
    assert {:ok, _room} =
             Collaboration.create_room(%{
               "room_id" => "room-relay-invalid-1",
               "brief" => "Exercise contribution rejection handling.",
               "rules" => [],
               "participants" => [
                 %{
                   "participant_id" => "worker-01",
                   "participant_role" => "worker",
                   "participant_kind" => "runtime",
                   "authority_level" => "advisory",
                   "target_id" => "target-worker-01",
                   "capability_id" => "codex.exec.session",
                   "metadata" => %{}
                 }
               ]
             })

    socket = %Phoenix.Socket{assigns: %{workspace_id: "workspace-1"}}

    payload = %{
      "room_id" => "room-relay-invalid-1",
      "participant_id" => "worker-01",
      "participant_role" => "worker",
      "target_id" => "target-worker-01",
      "capability_id" => "codex.exec.session",
      "contribution_type" => "reasoning",
      "authority_level" => "advisory",
      "summary" => "Invalid relation target.",
      "context_objects" => [
        %{
          "object_type" => "note",
          "title" => "Broken relation",
          "relations" => [
            %{"relation" => "derives_from", "target_id" => nil}
          ]
        }
      ],
      "execution" => %{"status" => "completed"},
      "status" => "completed"
    }

    assert {:reply, {:error, %{"error" => error}}, ^socket} =
             RelayChannel.handle_in("contribution.submit", payload, socket)

    assert error =~ "scope_violation"
    assert error =~ "missing_relation_target"
  end
end
