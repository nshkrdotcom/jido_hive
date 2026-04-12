defmodule JidoHiveSurface.RoomsTest do
  use ExUnit.Case, async: true

  alias JidoHiveSurface.Rooms

  defmodule OperatorStub do
    def list_saved_rooms(_api_base_url), do: ["room-1"]

    def fetch_room(_api_base_url, "room-1") do
      {:ok,
       %{
         "id" => "room-1",
         "name" => "Brief",
         "status" => "running",
         "assignment_counts" => %{"completed" => 1},
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
       }}
    end

    def list_room_events(_api_base_url, room_id, _opts),
      do: {:ok, %{entries: [], next_cursor: "#{room_id}:events"}}

    def create_room(_api_base_url, payload), do: {:ok, payload}
    def add_saved_room(_room_id, _api_base_url), do: :ok

    def start_room_run_operation(_api_base_url, _room_id, opts) do
      {:ok,
       %{"operation_id" => "room-run-1", "status" => "queued", "opts" => Enum.into(opts, %{})}}
    end

    def fetch_room_run_operation(_api_base_url, _room_id, operation_id, _opts) do
      {:ok, %{"operation_id" => operation_id, "status" => "completed"}}
    end
  end

  defmodule RoomSessionStub do
    def start_link(_opts), do: {:ok, :session}
    def submit_chat(:session, payload), do: {:ok, payload}
    def shutdown(:session), do: :ok
  end

  test "lists room catalog rows through the shared surface" do
    [room] = Rooms.list("http://127.0.0.1:4000/api", operator_module: OperatorStub)

    assert room.id == "room-1"
    assert room.name == "Brief"
    assert room.status == "running"
  end

  test "falls back to an operator default when the override is nil" do
    [room] =
      Rooms.list("http://127.0.0.1:4000/api",
        operator_module: nil,
        operator_module_fallback: OperatorStub
      )

    assert room.id == "room-1"
    assert room.name == "Brief"
    assert room.status == "running"
  end

  test "loads a structured room workspace" do
    workspace =
      Rooms.workspace("http://127.0.0.1:4000/api", "room-1", operator_module: OperatorStub)

    assert workspace.room_id == "room-1"
    assert workspace.control_plane.stage == "Review"
  end

  test "loads provenance from the shared surface" do
    assert {:error, :not_found} =
             Rooms.provenance("http://127.0.0.1:4000/api", "room-1", "ctx-1",
               operator_module: OperatorStub
             )
  end

  test "creates rooms and starts/fetches room run operations" do
    assert {:ok, %{"id" => "room-2", "name" => "Brief", "participants" => []}} =
             Rooms.create(
               "http://127.0.0.1:4000/api",
               %{
                 "id" => "room-2",
                 "name" => "Brief",
                 "participants" => []
               },
               operator_module: OperatorStub
             )

    assert {:ok, %{"operation_id" => "room-run-1", "status" => "queued", "opts" => opts}} =
             Rooms.run("http://127.0.0.1:4000/api", "room-2",
               operator_module: OperatorStub,
               max_assignments: 2,
               assignment_timeout_ms: 90_000
             )

    assert opts[:max_assignments] == 2
    assert opts[:assignment_timeout_ms] == 90_000

    assert {:ok, %{"operation_id" => "room-run-1", "status" => "completed"}} =
             Rooms.run_status("http://127.0.0.1:4000/api", "room-2", "room-run-1",
               operator_module: OperatorStub
             )
  end

  test "submits steering through a shared surface room-session handoff" do
    assert {:ok, %{text: "Need a binding decision"}} =
             Rooms.submit_steering(
               "http://127.0.0.1:4000/api",
               "room-1",
               %{
                 participant_id: "alice",
                 participant_role: "coordinator"
               },
               "Need a binding decision",
               room_session_module: RoomSessionStub
             )
  end

  test "falls back to a room-session default when the override is nil" do
    assert {:ok, %{text: "Need a binding decision"}} =
             Rooms.submit_steering(
               "http://127.0.0.1:4000/api",
               "room-1",
               %{
                 participant_id: "alice",
                 participant_role: "coordinator"
               },
               "Need a binding decision",
               room_session_module: nil,
               room_session_module_fallback: RoomSessionStub
             )
  end

  test "normalizes create attrs with generated defaults" do
    assert {:ok, payload} = Rooms.normalize_create_attrs(%{"name" => "Review this room"})
    assert is_binary(payload["id"])
    assert String.starts_with?(payload["id"], "room-")
    assert payload["name"] == "Review this room"
    assert payload["participants"] == []
  end

  test "validates required create attrs" do
    assert {:error, %{name: "can't be blank"}} = Rooms.normalize_create_attrs(%{})
  end

  test "normalizes run attrs from string inputs" do
    assert {:ok, opts} =
             Rooms.normalize_run_attrs(%{
               "max_assignments" => "2",
               "assignment_timeout_ms" => "90000"
             })

    assert opts[:max_assignments] == 2
    assert opts[:assignment_timeout_ms] == 90_000
  end

  test "rejects invalid run attrs" do
    assert {:error, %{max_assignments: "must be a positive integer"}} =
             Rooms.normalize_run_attrs(%{"max_assignments" => "0"})
  end
end
