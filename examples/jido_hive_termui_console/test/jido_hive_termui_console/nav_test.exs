defmodule JidoHiveTermuiConsole.NavTest do
  use ExUnit.Case, async: true

  alias JidoHiveTermuiConsole.{Model, Nav}

  defmodule OperatorStub do
    def list_saved_rooms(_api_base_url), do: ["room-a", "room-b"]

    def fetch_room(_base, "room-1") do
      {:ok,
       %{
         "room_id" => "room-1",
         "brief" => "Test room",
         "status" => "running",
         "dispatch_policy_id" => "round_robin/v2",
         "dispatch_state" => %{"completed_slots" => 1, "total_slots" => 3},
         "participants" => [%{"participant_id" => "worker-1"}]
       }}
    end

    def fetch_room(_base, "room-with-context") do
      {:ok,
       %{
         "room_id" => "room-with-context",
         "status" => "running",
         "timeline" => [%{"body" => "server timeline"}],
         "context_objects" => [
           %{
             "context_id" => "ctx-1",
             "object_type" => "note",
             "title" => "server context"
           }
         ],
         "dispatch_state" => %{"completed_slots" => 1, "total_slots" => 3},
         "participants" => []
       }}
    end

    def fetch_room(_base, _room_id), do: {:error, :not_found}
  end

  defmodule EmbeddedStub do
    def start_link(opts) do
      send(self(), {:embedded_start, opts})

      Agent.start_link(fn ->
        %{
          "timeline" => [],
          "context_objects" => [],
          "last_error" => nil
        }
      end)
    end

    def snapshot(server), do: Agent.get(server, & &1)
    def refresh(server), do: {:ok, snapshot(server)}

    def shutdown(server) do
      send(self(), {:embedded_shutdown, server})
      GenServer.stop(server)
      :ok
    end
  end

  defmodule PollerStub do
    def start_link(opts) do
      send(self(), {:poller_start, opts})
      {:ok, spawn(fn -> Process.sleep(:infinity) end)}
    end
  end

  defmodule EmbeddedSnapshotStub do
    def start_link(_opts) do
      Agent.start_link(fn ->
        %{
          "room_id" => "room-1",
          "status" => "publication_ready",
          "dispatch_state" => %{"completed_slots" => 2, "total_slots" => 2},
          "participants" => [%{"participant_id" => "worker-1"}],
          "timeline" => [%{"body" => "embedded timeline"}],
          "context_objects" => [
            %{"context_id" => "ctx-1", "object_type" => "note", "title" => "embedded context"}
          ],
          "last_error" => nil
        }
      end)
    end

    def snapshot(server), do: Agent.get(server, & &1)
    def refresh(server), do: {:ok, snapshot(server)}

    def shutdown(server) do
      GenServer.stop(server)
      :ok
    end
  end

  defmodule EmbeddedBlockingSnapshotStub do
    def start_link(opts) do
      send(self(), {:embedded_start, opts})

      Agent.start_link(fn ->
        %{
          "timeline" => [],
          "context_objects" => [],
          "last_error" => nil
        }
      end)
    end

    def snapshot(server) do
      send(self(), {:embedded_snapshot_called, server})
      Process.sleep(6_000)
      Agent.get(server, & &1)
    end

    def refresh(server), do: {:ok, Agent.get(server, & &1)}

    def shutdown(server) do
      send(self(), {:embedded_shutdown, server})
      GenServer.stop(server)
      :ok
    end
  end

  test "transition to lobby emits fetch messages per local room" do
    state = Model.new(operator_module: OperatorStub)
    next_state = Nav.transition(state, :lobby, app_pid: self())

    assert next_state.active_screen == :lobby
    assert next_state.lobby_rooms |> Enum.map(& &1.room_id) == ["room-a", "room-b"]
    assert_receive {:fetch_room, "room-a"}
    assert_receive {:fetch_room, "room-b"}
  end

  test "transition to room starts embedded and poller" do
    state =
      Model.new(
        api_base_url: "http://localhost:4000/api",
        embedded_module: EmbeddedStub,
        event_log_poller_module: PollerStub,
        operator_module: OperatorStub
      )

    next_state = Nav.transition(state, :room, room_id: "room-1", app_pid: self())

    assert next_state.active_screen == :room
    assert next_state.room_id == "room-1"
    assert is_pid(next_state.embedded)
    assert next_state.event_log_poller_pid == nil
    assert_receive {:embedded_start, _opts}
    refute_receive {:poller_start, _opts}, 50
  end

  test "transition to room does not snapshot embedded process during initial open" do
    state =
      Model.new(
        api_base_url: "http://localhost:4000/api",
        embedded_module: EmbeddedBlockingSnapshotStub,
        event_log_poller_module: PollerStub,
        operator_module: OperatorStub
      )

    next_state = Nav.transition(state, :room, room_id: "room-1", app_pid: self())

    assert next_state.active_screen == :room
    assert is_pid(next_state.embedded)
    refute_receive {:embedded_snapshot_called, _pid}, 50
  end

  test "transition to room preserves fetched server context when embedded snapshot is empty" do
    state =
      Model.new(
        api_base_url: "http://localhost:4000/api",
        embedded_module: EmbeddedStub,
        event_log_poller_module: PollerStub,
        operator_module: OperatorStub
      )

    next_state = Nav.transition(state, :room, room_id: "room-with-context", app_pid: self())

    assert next_state.snapshot["timeline"] == [%{"body" => "server timeline"}]

    assert next_state.snapshot["context_objects"] == [
             %{
               "context_id" => "ctx-1",
               "object_type" => "note",
               "title" => "server context"
             }
           ]
  end

  test "transition to missing room surfaces a direct error state" do
    state =
      Model.new(
        api_base_url: "http://localhost:4000/api",
        embedded_module: EmbeddedStub,
        event_log_poller_module: PollerStub,
        operator_module: OperatorStub
      )

    next_state = Nav.transition(state, :room, room_id: "missing-room", app_pid: self())

    assert next_state.active_screen == :room
    assert next_state.embedded == nil
    assert next_state.event_log_poller_pid == nil
    assert next_state.help_visible == false
    assert next_state.sync_error == true
    assert next_state.status_severity == :error
    assert next_state.status_line == "Room missing-room was not found on this server"
    assert next_state.snapshot["status"] == "not_found"
  end

  test "transition from room to lobby shuts down owned processes" do
    state =
      Model.new(
        api_base_url: "http://localhost:4000/api",
        embedded_module: EmbeddedStub,
        event_log_poller_module: PollerStub,
        operator_module: OperatorStub
      )
      |> Nav.transition(:room, room_id: "room-1", app_pid: self())

    next_state = Nav.transition(state, :lobby, app_pid: self())

    assert next_state.active_screen == :lobby
    assert_receive {:embedded_shutdown, _pid}
  end

  test "refresh_room_snapshot uses the embedded room session snapshot instead of operator fetches" do
    {:ok, embedded} = EmbeddedSnapshotStub.start_link([])

    state =
      Model.new(
        api_base_url: "http://localhost:4000/api",
        embedded: embedded,
        embedded_module: EmbeddedSnapshotStub,
        operator_module: OperatorStub,
        room_id: "room-1",
        snapshot: %{
          "room_id" => "room-1",
          "status" => "idle",
          "timeline" => [],
          "context_objects" => []
        }
      )

    next_state = Nav.refresh_room_snapshot(state)

    assert next_state.snapshot["status"] == "publication_ready"
    assert next_state.snapshot["timeline"] == [%{"body" => "embedded timeline"}]
    assert next_state.event_log_lines == ["event"]

    assert next_state.snapshot["context_objects"] == [
             %{"context_id" => "ctx-1", "object_type" => "note", "title" => "embedded context"}
           ]
  end

  test "transition to conflict populates left and right objects" do
    snapshot = %{
      "context_objects" => [
        %{
          "context_id" => "ctx-1",
          "object_type" => "belief",
          "title" => "left",
          "adjacency" => %{
            "incoming" => [],
            "outgoing" => [%{"type" => "contradicts", "target_id" => "ctx-2"}]
          }
        },
        %{"context_id" => "ctx-2", "object_type" => "belief", "title" => "right"}
      ]
    }

    state =
      Model.new(snapshot: snapshot)
      |> Map.put(:active_screen, :room)

    next_state = Nav.transition(state, :conflict)

    assert next_state.active_screen == :conflict
    assert next_state.conflict_left["context_id"] == "ctx-1"
    assert next_state.conflict_right["context_id"] == "ctx-2"
  end

  test "transition to conflict resolves partner from relations when adjacency is absent" do
    snapshot = %{
      "context_objects" => [
        %{
          "context_id" => "ctx-1",
          "object_type" => "decision",
          "title" => "left"
        },
        %{
          "context_id" => "ctx-2",
          "object_type" => "note",
          "title" => "right",
          "relations" => [%{"relation" => "contradicts", "target_id" => "ctx-1"}]
        }
      ]
    }

    state =
      Model.new(snapshot: snapshot)
      |> Map.put(:active_screen, :room)

    next_state = Nav.transition(state, :conflict)

    assert next_state.active_screen == :conflict
    assert next_state.conflict_left["context_id"] == "ctx-1"
    assert next_state.conflict_right["context_id"] == "ctx-2"
  end

  test "transition to publish and wizard enqueues fetch work" do
    state = Model.new(tenant_id: "workspace-demo", actor_id: "operator-demo")

    publish =
      Nav.transition(%{state | active_screen: :room, room_id: "room-1"}, :publish,
        app_pid: self()
      )

    assert_receive :fetch_publication_plan
    assert_receive :refresh_auth_state
    assert publish.tenant_id == "workspace-demo"
    assert publish.actor_id == "operator-demo"

    _wizard = Nav.transition(state, :wizard, app_pid: self())
    assert_receive :fetch_wizard_targets
    assert_receive :fetch_wizard_policies

    wizard = Nav.transition(state, :wizard, app_pid: self())
    assert wizard.wizard_targets_state == :loading
    assert wizard.wizard_policies_state == :loading
  end
end
