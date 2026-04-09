defmodule JidoHiveClient.RoomSessionTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.RoomSession

  test "sync_health reports degraded when the snapshot contains a last_error" do
    assert RoomSession.sync_health(%{
             "last_error" => :timeout,
             "last_sync_at" => "2026-04-08T23:59:00Z",
             "next_cursor" => "evt-2"
           }) == %{
             last_error: :timeout,
             last_sync_at: "2026-04-08T23:59:00Z",
             next_cursor: "evt-2",
             status: :degraded
           }
  end

  test "sync_health reports ok for empty snapshots" do
    assert RoomSession.sync_health(%{}) == %{
             last_error: nil,
             last_sync_at: nil,
             next_cursor: nil,
             status: :ok
           }
  end
end
