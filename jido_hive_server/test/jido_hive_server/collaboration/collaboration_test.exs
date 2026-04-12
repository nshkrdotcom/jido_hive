defmodule JidoHiveServer.CollaborationTest do
  use ExUnit.Case, async: false
  use JidoHiveServer.PersistenceCase

  alias JidoHiveServer.Collaboration
  alias JidoHiveServer.Collaboration.ParticipantSessionRegistry
  alias JidoHiveServer.Collaboration.RoomServer

  test "create_room replaces persisted room state for the same id" do
    assert {:ok, _snapshot} =
             Collaboration.create_room(%{
               id: "room-reuse-1",
               name: "Original room",
               config: %{},
               participants: [
                 %{id: "agent-1", kind: "agent", handle: "agent-1", meta: %{}}
               ]
             })

    assert {:ok, _snapshot} =
             Collaboration.submit_contribution("room-reuse-1", %{
               id: "ctrb-1",
               participant_id: "agent-1",
               kind: "note",
               payload: %{"text" => "Original contribution"}
             })

    assert {:ok, replaced} =
             Collaboration.create_room(%{
               id: "room-reuse-1",
               name: "Replacement room",
               config: %{},
               participants: [
                 %{id: "agent-1", kind: "agent", handle: "agent-1", meta: %{}}
               ]
             })

    assert replaced.room.name == "Replacement room"
    assert replaced.assignments == []
    assert replaced.contributions == []

    assert {:ok, events} = Collaboration.list_events("room-reuse-1")

    assert Enum.map(events, & &1.type) == [
             :room_created,
             :participant_joined,
             :room_phase_changed
           ]
  end

  test "dispatch_once creates assignments for available participants and contribution submission completes them" do
    assert {:ok, _snapshot} =
             Collaboration.create_room(%{
               id: "room-dispatch-1",
               name: "Dispatch room",
               config: %{"assignment_limit" => 1},
               participants: [
                 %{
                   id: "agent-1",
                   kind: "agent",
                   handle: "agent-1",
                   meta: %{"target_id" => "target-1"}
                 }
               ]
             })

    assert :ok =
             ParticipantSessionRegistry.register_session(%{
               room_id: "room-dispatch-1",
               session_id: "session-agent-1",
               pid: self(),
               mode: "participant",
               participant_id: "agent-1",
               participant_meta: %{"target_id" => "target-1"},
               caught_up: true
             })

    on_exit(fn ->
      ParticipantSessionRegistry.unregister_session("room-dispatch-1", "session-agent-1")
    end)

    assert {:ok, {:dispatch, ["asg-1"]}, dispatched_snapshot} =
             RoomServer.dispatch_once(RoomServer.via("room-dispatch-1"))

    assert [%{id: "asg-1", status: "pending"}] = dispatched_snapshot.assignments

    assert_receive {:assignment_offer, %{id: "asg-1", participant_id: "agent-1"}}, 200

    assert {:ok, completed_snapshot} =
             Collaboration.submit_contribution("room-dispatch-1", %{
               id: "ctrb-1",
               participant_id: "agent-1",
               assignment_id: "asg-1",
               kind: "reasoning",
               payload: %{"summary" => "Done"}
             })

    assert [%{id: "asg-1", status: "completed"}] = completed_snapshot.assignments
    assert [%{id: "ctrb-1", assignment_id: "asg-1"}] = completed_snapshot.contributions
  end
end
