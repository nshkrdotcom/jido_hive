defmodule JidoHiveClient.Boundary.RoomApi do
  @moduledoc false

  @callback fetch_room(keyword(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_events(keyword(), String.t(), keyword()) ::
              {:ok, %{entries: [map()], next_cursor: String.t() | nil}} | {:error, term()}
  @callback submit_contribution(keyword(), String.t(), map()) :: {:ok, map()} | {:error, term()}
end
