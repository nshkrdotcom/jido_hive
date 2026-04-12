defmodule JidoHiveSurface.AppKitSurface do
  @moduledoc """
  `app_kit`-backed operator and collaboration adapters over canonical room reads.
  """

  alias AppKit.ChatSurface
  alias AppKit.Core.RunRef
  alias AppKit.OperatorSurface
  alias AppKit.ScopeObjects
  alias JidoHiveSurface.Rooms

  @spec room_scope(String.t(), String.t(), String.t()) ::
          {:ok, AppKit.ScopeObjects.HostScope.t()} | {:error, atom()}
  def room_scope(api_base_url, room_id, actor_id)
      when is_binary(api_base_url) and is_binary(room_id) and is_binary(actor_id) do
    ScopeObjects.host_scope(%{
      scope_id: "room/#{room_id}",
      actor_id: actor_id,
      metadata: %{api_base_url: api_base_url, room_id: room_id}
    })
  end

  @spec room_run_surface(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def room_run_surface(api_base_url, room_id, operation_id, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_binary(operation_id) do
    with {:ok, scope} <-
           room_scope(
             api_base_url,
             room_id,
             Keyword.get(opts, :actor_id, "jido_hive_surface")
           ),
         workspace <- Rooms.workspace(api_base_url, room_id, opts),
         {:ok, operation} <- Rooms.run_status(api_base_url, room_id, operation_id, opts),
         {:ok, run_ref} <- RunRef.new(%{run_id: operation_id, scope_id: scope.scope_id}),
         {:ok, projection} <-
           OperatorSurface.run_status(
             run_ref,
             %{
               route_name: :room_run,
               state: route_state(operation),
               details: %{
                 room_id: workspace.room_id,
                 room_status: workspace.status,
                 stage: workspace.control_plane.stage
               },
               last_event: Map.get(operation, "status", "unknown")
             },
             config: Keyword.get(opts, :config)
           ) do
      {:ok,
       %{
         scope: scope,
         workspace: workspace,
         operation: operation,
         projection: projection
       }}
    end
  end

  @spec steering_surface(String.t(), String.t(), map(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def steering_surface(api_base_url, room_id, identity, text, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_map(identity) and is_binary(text) do
    actor_id =
      Map.get(identity, :participant_id) || Map.get(identity, "participant_id") || "operator"

    with {:ok, scope} <- room_scope(api_base_url, room_id, actor_id),
         {:ok, chat_result} <-
           ChatSurface.submit_turn(scope, text, config: Keyword.get(opts, :config)),
         {:ok, steering} <- Rooms.submit_steering(api_base_url, room_id, identity, text, opts) do
      {:ok, %{scope: scope, chat_result: chat_result, steering: steering}}
    end
  end

  defp route_state(operation) do
    case Map.get(operation, "status") || Map.get(operation, :status) do
      status when status in ["queued", :queued, "waiting", :waiting] -> :pending
      status when status in ["running", :running, "active", :active] -> :running
      status when status in ["completed", :completed, "done", :done] -> :completed
      status when status in ["failed", :failed, "error", :error] -> :failed
      _status -> :pending
    end
  end
end
