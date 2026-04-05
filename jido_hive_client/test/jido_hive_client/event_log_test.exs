defmodule JidoHiveClient.EventLogTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.EventLog

  test "appends events with monotonic ids and sequences" do
    log = EventLog.new(limit: 3)

    {log, first} =
      EventLog.append(log, %{
        type: "client.connection.changed",
        payload: %{"status" => "starting"}
      })

    {log, second} =
      EventLog.append(log, %{
        type: "client.job.received",
        room_id: "room-1",
        job_id: "job-1",
        payload: %{"phase" => "proposal"}
      })

    assert first.event_id == "client-event-1"
    assert first.sequence == 1
    assert second.event_id == "client-event-2"
    assert second.sequence == 2
    assert Enum.map(EventLog.list(log), & &1.event_id) == ["client-event-1", "client-event-2"]
  end

  test "truncates to a bounded history and supports cursor filtering" do
    log = EventLog.new(limit: 2)

    {log, _first} = EventLog.append(log, %{type: "client.connection.changed"})
    {log, second} = EventLog.append(log, %{type: "client.job.received", job_id: "job-2"})
    {log, third} = EventLog.append(log, %{type: "client.job.completed", job_id: "job-3"})

    assert Enum.map(EventLog.list(log), & &1.event_id) == ["client-event-2", "client-event-3"]
    assert [^third] = EventLog.list(log, after: second.event_id)
  end
end
