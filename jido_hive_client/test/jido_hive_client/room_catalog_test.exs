defmodule JidoHiveClient.RoomCatalogTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.RoomCatalog

  defmodule OperatorStub do
    def list_saved_rooms("https://example.com/api"), do: ["room-1", "missing-room"]

    def fetch_room("https://example.com/api", "room-1") do
      {:ok,
       %{
         "room_id" => "room-1",
         "brief" => "Stabilize auth path",
         "status" => "publication_ready",
         "dispatch_policy_id" => "rr",
         "dispatch_state" => %{"completed_slots" => 2, "total_slots" => 2},
         "participants" => [%{}, %{}]
       }}
    end

    def fetch_room("https://example.com/api", "missing-room"), do: {:error, :room_not_found}
  end

  test "loads room summaries from saved room ids" do
    rows = RoomCatalog.list("https://example.com/api", operator_module: OperatorStub)

    assert [
             %{
               room_id: "room-1",
               brief: "Stabilize auth path",
               status: "publication_ready",
               completed_slots: 2,
               total_slots: 2,
               participant_count: 2,
               fetch_error: false
             },
             %{
               room_id: "missing-room",
               fetch_error: true
             }
           ] = rows
  end
end
