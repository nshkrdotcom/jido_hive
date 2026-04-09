defmodule JidoHiveClient.RoomSession do
  @moduledoc """
  Room-scoped client session for human-facing tools and scriptable operator flows.

  This is the semantic boundary the TUI and headless CLI should consume.
  It delegates to the internal embedded session implementation.
  """

  alias JidoHiveClient.Embedded

  @type sync_health :: %{
          last_error: term() | nil,
          last_sync_at: term() | nil,
          next_cursor: term() | nil,
          status: :ok | :degraded
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: Embedded.start_link(opts)

  @spec snapshot(pid()) :: map()
  def snapshot(session), do: Embedded.snapshot(session)

  @spec subscribe(pid()) :: :ok | {:error, term()}
  def subscribe(session), do: Embedded.subscribe(session)

  @spec submit_chat(pid(), map()) :: {:ok, map()} | {:error, term()}
  def submit_chat(session, attrs), do: Embedded.submit_chat(session, attrs)

  @spec submit_chat_async(pid(), map()) :: {:ok, map()} | {:error, term()}
  def submit_chat_async(session, attrs), do: Embedded.submit_chat_async(session, attrs)

  @spec accept_context(pid(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def accept_context(session, context_id, attrs),
    do: Embedded.accept_context(session, context_id, attrs)

  @spec refresh(pid()) :: {:ok, map()} | {:error, term()}
  def refresh(session), do: Embedded.refresh(session)

  @spec shutdown(pid()) :: :ok
  def shutdown(session), do: Embedded.shutdown(session)

  @spec sync_health(map()) :: sync_health()
  def sync_health(snapshot) when is_map(snapshot) do
    last_error = Map.get(snapshot, "last_error") || Map.get(snapshot, :last_error)
    last_sync_at = Map.get(snapshot, "last_sync_at") || Map.get(snapshot, :last_sync_at)
    next_cursor = Map.get(snapshot, "next_cursor") || Map.get(snapshot, :next_cursor)

    %{
      last_error: last_error,
      last_sync_at: last_sync_at,
      next_cursor: next_cursor,
      status: if(is_nil(last_error), do: :ok, else: :degraded)
    }
  end

  def sync_health(_snapshot) do
    %{
      last_error: nil,
      last_sync_at: nil,
      next_cursor: nil,
      status: :ok
    }
  end
end
