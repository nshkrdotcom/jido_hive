defmodule JidoHiveServerWeb.RoomTimelineController do
  use JidoHiveServerWeb, :controller

  alias JidoHiveServer.{Collaboration, Persistence}
  alias JidoHiveServer.Collaboration.RoomTimeline

  def index(conn, %{"id" => room_id} = params) do
    case Collaboration.fetch_room(room_id) do
      {:ok, _snapshot} ->
        entries =
          room_id
          |> Persistence.list_room_events()
          |> RoomTimeline.project(after: params["after"])

        if stream_request?(conn, params) do
          stream_timeline(conn, entries, truthy?(params["once"]))
        else
          json(conn, %{data: entries, next_cursor: RoomTimeline.next_cursor(entries)})
        end

      {:error, :room_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "room_not_found"})
    end
  end

  defp stream_timeline(conn, entries, once?) do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> send_chunked(200)

    with {:ok, conn} <- emit_backlog(conn, entries),
         {:ok, conn} <- maybe_wait_for_events(conn, once?) do
      conn
    else
      {:error, _reason} -> conn
    end
  end

  defp maybe_wait_for_events(conn, true), do: {:ok, conn}

  defp maybe_wait_for_events(conn, false) do
    receive do
    after
      15_000 ->
        {:ok, conn}
    end
  end

  defp emit_backlog(conn, backlog) do
    Enum.reduce_while(backlog, {:ok, conn}, fn entry, {:ok, current_conn} ->
      case chunk(current_conn, sse_chunk(entry)) do
        {:ok, next_conn} -> {:cont, {:ok, next_conn}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp sse_chunk(entry) do
    "event: #{entry.kind}\ndata: #{Jason.encode!(entry)}\n\n"
  end

  defp stream_request?(conn, params) do
    truthy?(params["stream"]) or
      Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "text/event-stream"))
  end

  defp truthy?(value) when value in [true, "true", "1", 1], do: true
  defp truthy?(_other), do: false
end
