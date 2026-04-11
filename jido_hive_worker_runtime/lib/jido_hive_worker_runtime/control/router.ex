defmodule JidoHiveWorkerRuntime.Control.Router do
  @moduledoc false

  use Plug.Router

  alias JidoHiveWorkerRuntime.Runtime

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:dispatch)

  def init(opts), do: opts

  def call(conn, opts) do
    conn
    |> Plug.Conn.put_private(:jido_hive_control_opts, opts)
    |> super(opts)
  end

  get "/api/runtime" do
    send_json(conn, 200, Runtime.snapshot(runtime(conn)))
  end

  get "/api/runtime/assignments" do
    snapshot = Runtime.snapshot(runtime(conn))
    send_json(conn, 200, %{recent_assignments: snapshot.recent_assignments})
  end

  get "/api/runtime/events" do
    conn = fetch_query_params(conn)

    if stream_request?(conn) do
      stream_events(conn, runtime(conn))
    else
      events = Runtime.recent_events(runtime(conn), after: conn.params["after"])

      send_json(conn, 200, %{
        events: events,
        next_cursor: next_cursor(events)
      })
    end
  end

  post "/api/runtime/assignments/execute" do
    payload =
      case conn.body_params do
        %{"assignment" => %{} = assignment} -> assignment
        %{} = assignment -> assignment
        _other -> %{}
      end

    case Runtime.run_assignment(runtime(conn), payload) do
      {:ok, contribution} ->
        send_json(conn, 200, contribution)

      {:error, reason} ->
        send_json(conn, 422, %{error: inspect(reason)})
    end
  end

  post "/api/runtime/shutdown" do
    shutdown_fun =
      Keyword.get(conn.private[:jido_hive_control_opts], :shutdown_fun, &default_shutdown/0)

    conn = send_json(conn, 202, %{status: "accepted"})

    spawn(fn ->
      shutdown_fun.()
    end)

    conn
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end

  defp stream_events(conn, runtime) do
    :ok = Runtime.subscribe(runtime)
    backlog = Runtime.recent_events(runtime, after: conn.params["after"])
    once? = truthy?(conn.params["once"])

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> send_chunked(200)

    with {:ok, conn} <- emit_backlog(conn, backlog),
         {:ok, conn} <- maybe_wait_for_events(conn, once?) do
      conn
    else
      {:error, _reason} -> conn
    end
  end

  defp maybe_wait_for_events(conn, true), do: {:ok, conn}

  defp maybe_wait_for_events(conn, false) do
    receive do
      {:client_runtime_event, event} ->
        case chunk(conn, sse_chunk(event)) do
          {:ok, conn} -> maybe_wait_for_events(conn, false)
          {:error, reason} -> {:error, reason}
        end
    after
      15_000 ->
        {:ok, conn}
    end
  end

  defp emit_backlog(conn, backlog) do
    Enum.reduce_while(backlog, {:ok, conn}, fn event, {:ok, current_conn} ->
      case chunk(current_conn, sse_chunk(event)) do
        {:ok, next_conn} -> {:cont, {:ok, next_conn}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp sse_chunk(event) do
    "event: #{event.type}\ndata: #{Jason.encode!(event)}\n\n"
  end

  defp runtime(conn) do
    Keyword.get(conn.private[:jido_hive_control_opts], :runtime, Runtime)
  end

  defp next_cursor([]), do: nil
  defp next_cursor(events), do: events |> List.last() |> Map.fetch!(:event_id)

  defp stream_request?(conn) do
    truthy?(conn.params["stream"]) or
      Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "text/event-stream"))
  end

  defp truthy?(value) when value in [true, "true", "1", 1], do: true
  defp truthy?(_other), do: false

  defp default_shutdown do
    if Application.get_env(:jido_hive_worker_runtime, :control_shutdown_mode) == :noop do
      :ok
    else
      System.stop(0)
    end
  end
end
