defmodule JidoHive.Switchyard.Site.ClientTest do
  use ExUnit.Case, async: true

  alias JidoHive.Switchyard.Site.Client

  defmodule OperatorStub do
    def list_saved_rooms(_api_base_url), do: ["room-1"]

    def fetch_room(_api_base_url, "room-1") do
      {:ok, %{"room_id" => "room-1", "brief" => "Brief", "status" => "running"}}
    end

    def fetch_room_sync(_api_base_url, _room_id, _opts) do
      {:ok,
       %{
         room_snapshot: %{
           "room_id" => "room-1",
           "brief" => "Brief",
           "status" => "running",
           "workflow_summary" => %{
             "objective" => "Brief",
             "stage" => "Review",
             "next_action" => "Inspect contradiction",
             "publish_ready" => false,
             "publish_blockers" => [],
             "blockers" => [],
             "graph_counts" => %{"total" => 1},
             "focus_candidates" => []
           },
           "context_objects" => []
         },
         entries: [],
         context_objects: [],
         operations: [],
         next_cursor: nil
       }}
    end

    def fetch_publication_plan(_api_base_url, _room_id) do
      {:ok,
       %{
         "duplicate_policy" => "canonical_only",
         "source_entries" => ["decision"],
         "publications" => [
           %{
             "channel" => "github",
             "required_bindings" => [%{"field" => "repo"}],
             "draft" => %{"title" => "Draft", "body" => "Body"}
           }
         ]
       }}
    end

    def load_auth_state(_api_base_url, _subject) do
      %{"github" => %{status: :cached, connection_id: "conn-1"}}
    end

    def publish_room(_api_base_url, _room_id, payload), do: {:ok, payload}
  end

  defmodule RoomSessionStub do
    def start_link(_opts), do: {:ok, :session}
    def submit_chat(:session, payload), do: {:ok, payload}
    def shutdown(:session), do: :ok
  end

  test "lists room catalog rows through jido_hive_client seams" do
    [room] = Client.list_rooms("http://127.0.0.1:4000/api", operator_module: OperatorStub)

    assert room.room_id == "room-1"
    assert room.status == "running"
  end

  test "loads a structured room workspace" do
    workspace =
      Client.load_room_workspace("http://127.0.0.1:4000/api", "room-1",
        operator_module: OperatorStub
      )

    assert workspace.room_id == "room-1"
    assert workspace.control_plane.stage == "Review"
  end

  test "loads a publication workspace and submits steering" do
    publication_workspace =
      Client.load_publication_workspace("http://127.0.0.1:4000/api", "room-1", "alice",
        operator_module: OperatorStub
      )

    assert publication_workspace.ready?

    assert {:ok, %{text: "Need a binding decision"}} =
             Client.submit_steering(
               "http://127.0.0.1:4000/api",
               "room-1",
               %{
                 participant_id: "alice",
                 participant_role: "coordinator",
                 authority_level: "binding"
               },
               "Need a binding decision",
               room_session_module: RoomSessionStub
             )

    assert {:ok, payload} =
             Client.publish(
               "http://127.0.0.1:4000/api",
               "room-1",
               publication_workspace,
               %{"github" => %{"repo" => "nshkrdotcom/jido_hive"}},
               operator_module: OperatorStub
             )

    assert payload["channels"] == ["github"]
  end
end
