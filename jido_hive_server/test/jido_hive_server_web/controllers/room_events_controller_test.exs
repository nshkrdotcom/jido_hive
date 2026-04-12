defmodule JidoHiveServerWeb.RoomEventsControllerTest do
  use JidoHiveServerWeb.ConnCase, async: false

  test "returns canonical room events with sequence cursor pagination", %{conn: conn} do
    create_conn =
      post(conn, ~p"/api/rooms", %{
        "data" => %{
          "id" => "room-events-1",
          "name" => "Events room",
          "config" => %{},
          "participants" => []
        }
      })

    assert %{"data" => %{"room" => %{"id" => "room-events-1"}}} = json_response(create_conn, 201)

    contribution_conn =
      post(recycle(create_conn), ~p"/api/rooms/room-events-1/contributions", %{
        "data" => %{
          "id" => "ctrb-1",
          "participant_id" => "human-1",
          "kind" => "comment",
          "payload" => %{"text" => "hello"}
        }
      })

    assert %{"data" => _snapshot} = json_response(contribution_conn, 200)

    events_conn = get(recycle(create_conn), ~p"/api/rooms/room-events-1/events?limit=1")

    assert %{
             "data" => [%{"id" => _event_id, "sequence" => 1, "type" => "room_created"}],
             "meta" => %{
               "schema_version" => "jido_hive/http.v1",
               "has_more" => true,
               "next_after_sequence" => 1
             }
           } = json_response(events_conn, 200)

    next_conn = get(recycle(create_conn), ~p"/api/rooms/room-events-1/events?after=1")

    assert %{
             "data" => [
               %{"sequence" => 2, "type" => "room_phase_changed"},
               %{"sequence" => 3, "type" => "contribution_submitted"}
             ],
             "meta" => %{
               "schema_version" => "jido_hive/http.v1",
               "has_more" => false,
               "next_after_sequence" => 3
             }
           } = json_response(next_conn, 200)
  end
end
