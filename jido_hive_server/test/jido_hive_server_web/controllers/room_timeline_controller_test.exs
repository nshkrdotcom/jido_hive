defmodule JidoHiveServerWeb.RoomTimelineControllerTest do
  use JidoHiveServerWeb.ConnCase, async: false

  alias JidoHiveServer.Collaboration.Schema.RoomEvent
  alias JidoHiveServer.Persistence

  test "returns the room timeline for a created room", %{conn: conn} do
    create_conn =
      post(conn, ~p"/api/rooms", %{
        "room_id" => "room-timeline-1",
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

    assert %{"data" => %{"room_id" => "room-timeline-1"}} = json_response(create_conn, 201)

    timeline_conn = get(recycle(create_conn), ~p"/api/rooms/room-timeline-1/timeline")

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
    create_conn =
      post(conn, ~p"/api/rooms", %{
        "room_id" => "room-timeline-2",
        "brief" => "Design a generalized substrate.",
        "rules" => [],
        "participants" => [
          %{
            "participant_id" => "worker-01",
            "role" => "worker",
            "target_id" => "target-worker-01",
            "capability_id" => "codex.exec.session"
          }
        ]
      })

    assert %{"data" => %{"room_id" => "room-timeline-2"}} = json_response(create_conn, 201)

    [%{"event_id" => first_event_id}] =
      json_response(get(recycle(create_conn), ~p"/api/rooms/room-timeline-2/events"), 200)["data"]

    {:ok, event} =
      RoomEvent.new(%{
        event_id: "evt-turn-opened-room-timeline-2",
        room_id: "room-timeline-2",
        type: :turn_opened,
        payload: %{
          job_id: "job-room-timeline-2",
          phase: "proposal",
          participant_id: "worker-01",
          participant_role: "proposer",
          target_id: "target-worker-01"
        },
        recorded_at: DateTime.utc_now()
      })

    assert :ok = Persistence.append_room_events("room-timeline-2", [event])

    timeline_conn =
      get(recycle(create_conn), ~p"/api/rooms/room-timeline-2/timeline?after=#{first_event_id}")

    assert %{
             "data" => [
               %{
                 "kind" => "turn.dispatched",
                 "job_id" => "job-room-timeline-2",
                 "room_id" => "room-timeline-2",
                 "schema_version" => "jido_hive/room_timeline_entry.v1"
               }
             ]
           } = json_response(timeline_conn, 200)
  end

  test "streams the room timeline backlog over SSE", %{conn: conn} do
    create_conn =
      post(conn, ~p"/api/rooms", %{
        "room_id" => "room-timeline-3",
        "brief" => "Design a generalized substrate.",
        "rules" => [],
        "participants" => [
          %{
            "participant_id" => "worker-01",
            "role" => "worker",
            "target_id" => "target-worker-01",
            "capability_id" => "codex.exec.session"
          }
        ]
      })

    assert %{"data" => %{"room_id" => "room-timeline-3"}} = json_response(create_conn, 201)

    conn =
      build_conn(:get, "/api/rooms/room-timeline-3/timeline?stream=true&once=true")
      |> put_req_header("accept", "text/event-stream")
      |> JidoHiveServerWeb.Endpoint.call([])

    assert conn.status == 200
    assert List.first(get_resp_header(conn, "content-type")) =~ "text/event-stream"
    assert conn.resp_body =~ "event: room.created"
    assert conn.resp_body =~ "\"kind\":\"room.created\""
  end
end
