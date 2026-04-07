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

    assert %{
             "data" => [
               %{
                 "context_id" => ^context_id,
                 "object_type" => "decision",
                 "adjacency" => %{"incoming" => [], "outgoing" => []}
               }
             ]
           } =
             json_response(index_conn, 200)

    show_conn =
      get(recycle(index_conn), ~p"/api/rooms/room-context-1/context_objects/#{context_id}")

    assert %{
             "data" => %{
               "context_id" => ^context_id,
               "title" => "Proceed",
               "adjacency" => %{"incoming" => [], "outgoing" => []}
             }
           } =
             json_response(show_conn, 200)
  end

  test "shows derived stale annotations and graph adjacency on context detail", %{conn: conn} do
    create_room(conn, "room-context-2")

    first_contribution =
      post(recycle(conn), ~p"/api/rooms/room-context-2/contributions", %{
        "participant_id" => "human-1",
        "participant_role" => "reviewer",
        "participant_kind" => "human",
        "contribution_type" => "perspective",
        "authority_level" => "binding",
        "summary" => "Add a fact.",
        "context_objects" => [
          %{
            "object_type" => "fact",
            "title" => "Original fact"
          }
        ]
      })

    assert %{
             "data" => %{
               "context_objects" => [
                 %{"context_id" => "ctx-1"}
               ]
             }
           } = json_response(first_contribution, 201)

    second_contribution =
      post(recycle(first_contribution), ~p"/api/rooms/room-context-2/contributions", %{
        "participant_id" => "human-1",
        "participant_role" => "reviewer",
        "participant_kind" => "human",
        "contribution_type" => "perspective",
        "authority_level" => "binding",
        "summary" => "Add a derived note.",
        "context_objects" => [
          %{
            "object_type" => "note",
            "title" => "Derived note",
            "relations" => [
              %{"relation" => "derives_from", "target_id" => "ctx-1"}
            ]
          }
        ]
      })

    assert %{"data" => %{"context_objects" => context_objects}} =
             json_response(second_contribution, 201)

    assert Enum.any?(context_objects, &(&1["context_id"] == "ctx-2"))

    _second_contribution =
      post(recycle(second_contribution), ~p"/api/rooms/room-context-2/contributions", %{
        "participant_id" => "human-1",
        "participant_role" => "reviewer",
        "participant_kind" => "human",
        "contribution_type" => "perspective",
        "authority_level" => "binding",
        "summary" => "Supersede the original fact.",
        "context_objects" => [
          %{
            "object_type" => "fact",
            "title" => "Replacement fact",
            "relations" => [
              %{"relation" => "supersedes", "target_id" => "ctx-1"}
            ]
          }
        ]
      })

    show_conn = get(recycle(conn), ~p"/api/rooms/room-context-2/context_objects/ctx-2")

    assert %{
             "data" => %{
               "context_id" => "ctx-2",
               "derived" => %{
                 "stale_ancestor" => true,
                 "stale_due_to_ids" => ["ctx-1"]
               },
               "adjacency" => %{
                 "outgoing" => [%{"type" => "derives_from", "to_id" => "ctx-1"}]
               }
             }
           } = json_response(show_conn, 200)
  end

  test "shows adjacency for canonical derives_from relations on decision detail", %{conn: conn} do
    create_room(conn, "room-context-3")

    first_contribution =
      post(recycle(conn), ~p"/api/rooms/room-context-3/contributions", %{
        "participant_id" => "human-1",
        "participant_role" => "reviewer",
        "participant_kind" => "human",
        "contribution_type" => "perspective",
        "authority_level" => "binding",
        "summary" => "Add a candidate.",
        "context_objects" => [
          %{
            "object_type" => "decision_candidate",
            "title" => "Candidate"
          }
        ]
      })

    assert %{
             "data" => %{
               "context_objects" => [
                 %{"context_id" => "ctx-1"}
               ]
             }
           } = json_response(first_contribution, 201)

    second_contribution =
      post(recycle(first_contribution), ~p"/api/rooms/room-context-3/contributions", %{
        "participant_id" => "human-1",
        "participant_role" => "reviewer",
        "participant_kind" => "human",
        "contribution_type" => "decision",
        "authority_level" => "binding",
        "summary" => "Accept the candidate.",
        "context_objects" => [
          %{
            "object_type" => "decision",
            "title" => "Accepted decision",
            "relations" => [
              %{"relation" => "derives_from", "target_id" => "ctx-1"}
            ]
          }
        ]
      })

    assert %{"data" => %{"context_objects" => context_objects}} =
             json_response(second_contribution, 201)

    assert Enum.any?(context_objects, &(&1["context_id"] == "ctx-2"))

    show_conn = get(recycle(conn), ~p"/api/rooms/room-context-3/context_objects/ctx-2")

    assert %{
             "data" => %{
               "context_id" => "ctx-2",
               "adjacency" => %{
                 "incoming" => [],
                 "outgoing" => [%{"type" => "derives_from", "to_id" => "ctx-1"}]
               }
             }
           } = json_response(show_conn, 200)
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
