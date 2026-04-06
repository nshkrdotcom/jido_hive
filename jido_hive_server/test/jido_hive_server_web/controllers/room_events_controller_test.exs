defmodule JidoHiveServerWeb.RoomEventsControllerTest do
  use JidoHiveServerWeb.ConnCase, async: false

  test "returns the room event stream for a created room", %{conn: conn} do
    create_conn =
      post(conn, ~p"/api/rooms", %{
        "room_id" => "room-events-1",
        "brief" => "Design a generalized substrate.",
        "rules" => ["Track all mutations as events."],
        "dispatch_policy_id" => "human_gate/v1",
        "participants" => []
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
