defmodule JidoHiveServerWeb.RelayChannelDuplicateTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias JidoHiveServer.Collaboration
  alias JidoHiveServerWeb.RelayChannel

  test "returns an error reply for conflicting duplicate contribution ids" do
    assert {:ok, _room} =
             Collaboration.create_room(%{
               "room_id" => "room-relay-duplicate-id-1",
               "brief" => "Detect duplicate contribution ids.",
               "rules" => [],
               "participants" => [
                 %{
                   "participant_id" => "worker-01",
                   "participant_role" => "worker",
                   "participant_kind" => "runtime",
                   "authority_level" => "advisory",
                   "target_id" => "target-worker-01",
                   "capability_id" => "workspace.exec.session",
                   "metadata" => %{}
                 },
                 %{
                   "participant_id" => "worker-02",
                   "participant_role" => "worker",
                   "participant_kind" => "runtime",
                   "authority_level" => "advisory",
                   "target_id" => "target-worker-02",
                   "capability_id" => "workspace.exec.session",
                   "metadata" => %{}
                 }
               ]
             })

    socket = %Phoenix.Socket{assigns: %{workspace_id: "workspace-1"}}

    first_payload = %{
      "room_id" => "room-relay-duplicate-id-1",
      "assignment_id" => "asn-1",
      "participant_id" => "worker-01",
      "participant_role" => "worker",
      "target_id" => "target-worker-01",
      "capability_id" => "workspace.exec.session",
      "contribution_id" => "contrib-shared-id",
      "contribution_type" => "reasoning",
      "authority_level" => "advisory",
      "summary" => "First contribution.",
      "context_objects" => [%{"object_type" => "note", "title" => "first"}],
      "execution" => %{"status" => "completed"},
      "status" => "completed"
    }

    second_payload =
      first_payload
      |> Map.put("assignment_id", "asn-2")
      |> Map.put("participant_id", "worker-02")
      |> Map.put("target_id", "target-worker-02")
      |> Map.put("summary", "Second contribution.")

    assert {:reply, {:ok, %{"accepted" => true}}, ^socket} =
             RelayChannel.handle_in("contribution.submit", first_payload, socket)

    assert {:reply, {:error, %{"error" => error}}, ^socket} =
             RelayChannel.handle_in("contribution.submit", second_payload, socket)

    assert error =~ "duplicate_contribution_id_conflict"
    assert error =~ "contrib-shared-id"
  end
end
