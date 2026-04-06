defmodule JidoHiveServerWeb.RoomTimelineControllerTest do
  use JidoHiveServerWeb.ConnCase, async: false

  alias JidoHiveServer.Collaboration.Schema.RoomEvent
  alias JidoHiveServer.Persistence

  test "returns the room timeline for a created room", %{conn: conn} do
    create_room(conn, "room-timeline-1")

    timeline_conn = get(recycle(conn), ~p"/api/rooms/room-timeline-1/timeline")

    assert %{
             "data" => [
               %{
                 "event_id" => _event_id,
                 "kind" => "room.created",
                 "room_id" => "room-timeline-1",
                 "schema_version" => "jido_hive/room_timeline_entry.v1",
                 "timestamp" => _timestamp
               }
             ],
             "next_cursor" => _cursor
           } = json_response(timeline_conn, 200)
  end

  test "filters the room timeline by cursor", %{conn: conn} do
    create_room(conn, "room-timeline-2")

    [%{"event_id" => first_event_id}] =
      json_response(get(recycle(conn), ~p"/api/rooms/room-timeline-2/events"), 200)["data"]

    {:ok, event} =
      RoomEvent.new(%{
        event_id: "evt-assignment-opened-room-timeline-2",
        room_id: "room-timeline-2",
        type: :assignment_opened,
        payload: %{
          assignment: %{
            assignment_id: "asn-room-timeline-2",
            phase: "analysis",
            participant_id: "worker-01",
            participant_role: "worker",
            target_id: "target-worker-01",
            objective: "Analyze the brief."
          }
        },
        recorded_at: DateTime.utc_now()
      })

    assert :ok = Persistence.append_room_events("room-timeline-2", [event])

    timeline_conn =
      get(recycle(conn), ~p"/api/rooms/room-timeline-2/timeline?after=#{first_event_id}")

    assert %{
             "data" => [
               %{
                 "kind" => "assignment.started",
                 "assignment_id" => "asn-room-timeline-2",
                 "room_id" => "room-timeline-2",
                 "schema_version" => "jido_hive/room_timeline_entry.v1"
               }
             ]
           } = json_response(timeline_conn, 200)
  end

  test "streams the room timeline backlog over SSE", %{conn: conn} do
    create_room(conn, "room-timeline-3")

    conn =
      build_conn(:get, "/api/rooms/room-timeline-3/timeline?stream=true&once=true")
      |> put_req_header("accept", "text/event-stream")
      |> JidoHiveServerWeb.Endpoint.call([])

    assert conn.status == 200
    assert List.first(get_resp_header(conn, "content-type")) =~ "text/event-stream"
    assert conn.resp_body =~ "event: room.created"
    assert conn.resp_body =~ "\"kind\":\"room.created\""
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
