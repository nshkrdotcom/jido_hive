defmodule JidoHiveClient.SessionEventLogTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.SessionEventLog

  test "appends session events with monotonic ids and sequences" do
    log = SessionEventLog.new(limit: 3)

    {log, first} =
      SessionEventLog.append(log, %{
        type: "session.connection.changed",
        payload: %{"status" => "ready"}
      })

    {log, second} =
      SessionEventLog.append(log, %{
        type: "embedded.chat.submitted",
        room_id: "room-1",
        payload: %{"chars" => 12}
      })

    assert first.event_id == "session-event-1"
    assert first.sequence == 1
    assert second.event_id == "session-event-2"
    assert second.sequence == 2

    assert Enum.map(SessionEventLog.list(log), & &1.event_id) == [
             "session-event-1",
             "session-event-2"
           ]
  end

  test "truncates to a bounded history and supports cursor filtering" do
    log = SessionEventLog.new(limit: 2)

    {log, _first} = SessionEventLog.append(log, %{type: "session.connection.changed"})
    {log, second} = SessionEventLog.append(log, %{type: "embedded.chat.accepted"})
    {log, third} = SessionEventLog.append(log, %{type: "embedded.chat.completed"})

    assert Enum.map(SessionEventLog.list(log), & &1.event_id) == [
             "session-event-2",
             "session-event-3"
           ]

    assert [^third] = SessionEventLog.list(log, after: second.event_id)
  end
end
