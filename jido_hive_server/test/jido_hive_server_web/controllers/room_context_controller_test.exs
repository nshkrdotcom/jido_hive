defmodule JidoHiveServerWeb.RoomContextControllerTest do
  use JidoHiveServerWeb.ConnCase, async: false

  test "lists and shows room context objects", %{conn: conn} do
    create_room(conn, "room-context-1")

    contribution_conn =
      post(recycle(conn), ~p"/api/rooms/room-context-1/contributions", %{
        "participant_id" => "human-1",
        "participant_role" => "reviewer",
        "participant_kind" => "human",
        "contribution_type" => "perspective",
        "authority_level" => "binding",
        "summary" => "Added a human decision.",
        "context_objects" => [
          %{
            "object_type" => "decision",
            "title" => "Proceed",
            "body" => "Proceed with implementation."
          }
        ]
      })

    assert %{"data" => %{"context_objects" => [%{"context_id" => context_id}]}} =
             json_response(contribution_conn, 201)

    index_conn = get(recycle(contribution_conn), ~p"/api/rooms/room-context-1/context_objects")

    assert %{"data" => [%{"context_id" => ^context_id, "object_type" => "decision"}]} =
             json_response(index_conn, 200)

    show_conn =
      get(recycle(index_conn), ~p"/api/rooms/room-context-1/context_objects/#{context_id}")

    assert %{"data" => %{"context_id" => ^context_id, "title" => "Proceed"}} =
             json_response(show_conn, 200)
  end

  defp create_room(conn, room_id) do
    create_conn =
      post(conn, ~p"/api/rooms", %{
        "room_id" => room_id,
        "brief" => "Design a generalized substrate.",
        "rules" => [],
        "dispatch_policy_id" => "human_gate/v1",
        "participants" => []
      })

    assert %{"data" => %{"room_id" => ^room_id}} = json_response(create_conn, 201)
    create_conn
  end
end
