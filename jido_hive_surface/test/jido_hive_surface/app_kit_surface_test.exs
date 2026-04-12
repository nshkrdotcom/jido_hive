defmodule JidoHiveSurface.AppKitSurfaceTest do
  use ExUnit.Case, async: true

  alias JidoHiveSurface.AppKitSurface

  defmodule OperatorStub do
    def fetch_room_sync(_api_base_url, room_id, _opts) do
      {:ok,
       %{
         room_snapshot: %{
           "room_id" => room_id,
           "brief" => "Brief",
           "status" => "running",
           "workflow_summary" => %{
             "objective" => "Brief",
             "stage" => "Review",
             "next_action" => "Inspect contradiction"
           },
           "context_objects" => []
         },
         entries: [],
         context_objects: [],
         operations: [%{"operation_id" => "room-run-1", "status" => "running"}],
         next_cursor: nil
       }}
    end

    def fetch_room_run_operation(_api_base_url, _room_id, operation_id, _opts) do
      {:ok, %{"operation_id" => operation_id, "status" => "running"}}
    end
  end

  defmodule RoomSessionStub do
    def start_link(_opts), do: {:ok, :session}
    def submit_chat(:session, payload), do: {:ok, payload}
    def shutdown(:session), do: :ok
  end

  test "projects the synced room workspace through app_kit operator surfaces" do
    assert {:ok, surface} =
             AppKitSurface.room_run_surface(
               "http://127.0.0.1:4000/api",
               "room-1",
               "room-run-1",
               operator_module: OperatorStub
             )

    assert surface.scope.scope_id == "room/room-1"
    assert surface.workspace.room_id == "room-1"
    assert surface.workspace.control_plane.stage == "Review"
    assert surface.operation["operation_id"] == "room-run-1"
    assert surface.projection.run_id == "room-run-1"
    assert surface.projection.route_status.route_name == :room_run
    assert surface.projection.route_status.state == :running
    assert surface.projection.route_status.details.room_status == "running"
  end

  test "projects steering through app_kit chat surfaces before room-session delivery" do
    assert {:ok, result} =
             AppKitSurface.steering_surface(
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

    assert result.scope.scope_id == "room/room-1"
    assert result.chat_result.surface == :conversation
    assert result.chat_result.state == :accepted
    assert result.chat_result.payload.turn.actor_id == "alice"
    assert result.steering.text == "Need a binding decision"
  end
end
