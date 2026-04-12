defmodule JidoHiveServerWeb.RoomControllerTest do
  use JidoHiveServerWeb.ConnCase, async: false

  test "creates, shows, patches, lists, and closes canonical rooms", %{conn: conn} do
    create_conn =
      post(conn, ~p"/api/rooms", %{
        "data" => %{
          "id" => "room-http-1",
          "name" => "HTTP room",
          "phase" => "analysis",
          "config" => %{"dispatch_policy" => "round_robin/v2"},
          "participants" => [
            %{
              "id" => "human-1",
              "kind" => "human",
              "handle" => "alice",
              "meta" => %{"role" => "operator"}
            }
          ]
        }
      })

    assert %{
             "data" => %{
               "room" => %{
                 "id" => "room-http-1",
                 "name" => "HTTP room",
                 "status" => "waiting",
                 "phase" => "analysis"
               },
               "participants" => [%{"id" => "human-1", "kind" => "human", "handle" => "alice"}],
               "assignment_counts" => %{
                 "pending" => 0,
                 "active" => 0,
                 "completed" => 0,
                 "expired" => 0
               },
               "contribution_count" => 0
             },
             "meta" => %{"schema_version" => "jido_hive/http.v1"}
           } = json_response(create_conn, 201)

    show_conn = get(recycle(create_conn), ~p"/api/rooms/room-http-1")

    assert %{
             "data" => %{
               "room" => %{"id" => "room-http-1", "name" => "HTTP room", "phase" => "analysis"}
             }
           } = json_response(show_conn, 200)

    patch_conn =
      patch(recycle(create_conn), ~p"/api/rooms/room-http-1", %{
        "data" => %{"name" => "Renamed room", "phase" => "review"}
      })

    assert %{
             "data" => %{
               "room" => %{"id" => "room-http-1", "name" => "Renamed room", "phase" => "review"}
             }
           } = json_response(patch_conn, 200)

    index_conn = get(recycle(create_conn), ~p"/api/rooms")

    assert %{
             "data" => [
               %{
                 "room" => %{"id" => "room-http-1", "name" => "Renamed room", "phase" => "review"}
               }
             ]
           } = json_response(index_conn, 200)

    delete_conn = delete(recycle(create_conn), ~p"/api/rooms/room-http-1")

    assert %{
             "data" => %{
               "room" => %{"id" => "room-http-1", "status" => "closed"}
             }
           } = json_response(delete_conn, 200)
  end

  test "rejects create payloads outside the canonical data envelope", %{conn: conn} do
    create_conn =
      post(conn, ~p"/api/rooms", %{
        "id" => "room-http-invalid-1",
        "name" => "Missing envelope"
      })

    assert %{
             "error" => %{
               "code" => "invalid_room",
               "message" => "expected data payload"
             }
           } = json_response(create_conn, 422)
  end
end
