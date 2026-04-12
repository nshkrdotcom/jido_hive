defmodule JidoHiveWorkerRuntime.Boundary.ServerAPI do
  @moduledoc false

  @callback list_rooms(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  @callback list_room_events(String.t(), String.t(), integer()) ::
              {:ok, [map()]} | {:error, term()}
  @callback upsert_target(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback mark_target_offline(String.t(), String.t()) :: :ok | {:error, term()}
end
