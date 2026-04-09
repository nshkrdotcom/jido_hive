defmodule JidoHiveClient.DebugTraceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias JidoHiveClient.DebugTrace

  setup do
    previous = Application.get_env(:jido_hive_client, :debug_trace_level)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:jido_hive_client, :debug_trace_level)
      else
        Application.put_env(:jido_hive_client, :debug_trace_level, previous)
      end
    end)

    :ok
  end

  test "emits structured stderr json when enabled" do
    Application.put_env(:jido_hive_client, :debug_trace_level, :debug)

    output =
      capture_io(:stderr, fn ->
        :ok =
          DebugTrace.emit(:debug, "operator.http.request.started", %{
            operation_id: "op-123",
            method: "GET",
            path: "/rooms/room-1"
          })
      end)

    assert %{
             "app" => "jido_hive_client",
             "event" => "operator.http.request.started",
             "level" => "debug",
             "metadata" => %{
               "method" => "GET",
               "operation_id" => "op-123",
               "path" => "/rooms/room-1"
             },
             "ts" => _timestamp
           } = Jason.decode!(output)
  end

  test "suppresses lower-priority events when configured at info" do
    Application.put_env(:jido_hive_client, :debug_trace_level, :info)

    output =
      capture_io(:stderr, fn ->
        :ok = DebugTrace.emit(:debug, "operator.http.request.started", %{})
      end)

    assert output == ""
  end

  test "stays silent when trace is disabled" do
    Application.delete_env(:jido_hive_client, :debug_trace_level)

    output =
      capture_io(:stderr, fn ->
        :ok = DebugTrace.emit(:info, "headless.command.started", %{})
      end)

    assert output == ""
  end
end
