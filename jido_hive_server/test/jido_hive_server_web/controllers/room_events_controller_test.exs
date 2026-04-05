defmodule JidoHiveServerWeb.RoomEventsControllerTest do
  use JidoHiveServerWeb.ConnCase, async: false

  test "returns the room event stream for a created room", %{conn: conn} do
    create_conn =
      post(conn, ~p"/api/rooms", %{
        "room_id" => "room-events-1",
        "brief" => "Design a generalized substrate.",
        "rules" => ["Track all mutations as events."],
        "participants" => [
          %{
            "participant_id" => "worker-01",
            "role" => "worker",
            "target_id" => "target-worker-01",
            "capability_id" => "codex.exec.session"
          }
        ]
      })

    assert %{"data" => %{"room_id" => "room-events-1"}} = json_response(create_conn, 201)

    events_conn = get(recycle(create_conn), ~p"/api/rooms/room-events-1/events")

    assert %{
             "data" => [
               %{
                 "event_id" => _event_id,
                 "type" => "room_created",
                 "room_id" => "room-events-1"
               }
             ]
           } = json_response(events_conn, 200)
  end
end
