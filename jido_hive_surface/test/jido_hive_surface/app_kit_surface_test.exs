defmodule JidoHiveSurface.AppKitSurfaceTest do
  use ExUnit.Case, async: true

  alias Citadel.DomainSurface.Adapters.CitadelAdapter.Accepted
  alias JidoHiveSurface.AppKitSurface

  defmodule FakeKernelRuntime do
    def dispatch_command(command, _opts) do
      {:ok,
       Accepted.new!(%{
         request_id: command.idempotency_key,
         session_id: command.context[:session_id],
         trace_id: command.trace_id,
         ingress_path: :direct_intent_envelope,
         lifecycle_event: :live_owner,
         continuity_revision: 1
       })}
    end
  end

  defmodule OperatorStub do
    def fetch_room(_api_base_url, room_id) do
      {:ok,
       %{
         "id" => room_id,
         "name" => "Brief",
         "status" => "running",
         "workflow_summary" => %{
           "objective" => "Brief",
           "stage" => "Review",
           "next_action" => "Inspect contradiction"
         },
         "context_objects" => []
       }}
    end

    def list_room_events(_api_base_url, _room_id, _opts) do
      {:ok,
       %{
         entries: [],
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
                 participant_role: "coordinator"
               },
               "Need a binding decision",
               room_session_module: RoomSessionStub,
               idempotency_key: "jido-hive-steering-1",
               domain_module: Citadel.DomainSurface.Examples.ProvingGround,
               route_sources: [
                 Citadel.DomainSurface.Examples.ProvingGround.Routes.CompileWorkspace
               ],
               kernel_runtime: {FakeKernelRuntime, []}
             )

    assert result.scope.scope_id == "room/room-1"
    assert result.scope.session_id == "room/room-1/session"
    assert result.scope.tenant_id == "jido-hive"
    assert result.chat_result.surface == :conversation
    assert result.chat_result.state == :accepted
    assert result.chat_result.payload.accepted.request_id == "jido-hive-steering-1"

    assert result.chat_result.payload.action_request.args["objective"] ==
             "Need a binding decision"

    assert result.steering.text == "Need a binding decision"
  end
end
