defmodule JidoHiveTermuiConsole.NavTest do
  use ExUnit.Case, async: true

  alias JidoHiveTermuiConsole.{Model, Nav}

  defmodule ConfigStub do
    def list_rooms, do: ["room-a", "room-b"]
  end

  defmodule HTTPStub do
    def get(_base, "/rooms/room-1") do
      {:ok,
       %{
         "data" => %{
           "room_id" => "room-1",
           "brief" => "Test room",
           "status" => "running",
           "dispatch_policy_id" => "round_robin/v2",
           "dispatch_state" => %{"completed_slots" => 1, "total_slots" => 3},
           "participants" => [%{"participant_id" => "worker-1"}]
         }
       }}
    end

    def get(_base, _path), do: {:error, :not_found}
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

  test "transition to lobby emits fetch messages per local room" do
    state = Model.new(config_module: ConfigStub)
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
        http_module: HTTPStub
      )

    next_state = Nav.transition(state, :room, room_id: "room-1", app_pid: self())

    assert next_state.active_screen == :room
    assert next_state.room_id == "room-1"
    assert is_pid(next_state.embedded)
    assert is_pid(next_state.event_log_poller_pid)
    assert_receive {:embedded_start, _opts}
    assert_receive {:poller_start, _opts}
  end

  test "transition from room to lobby shuts down owned processes" do
    state =
      Model.new(
        api_base_url: "http://localhost:4000/api",
        embedded_module: EmbeddedStub,
        event_log_poller_module: PollerStub,
        http_module: HTTPStub
      )
      |> Nav.transition(:room, room_id: "room-1", app_pid: self())

    next_state = Nav.transition(state, :lobby, app_pid: self())

    assert next_state.active_screen == :lobby
    assert_receive {:embedded_shutdown, _pid}
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

  test "transition to publish and wizard enqueues fetch work" do
    state = Model.new([])

    _publish =
      Nav.transition(%{state | active_screen: :room, room_id: "room-1"}, :publish,
        app_pid: self()
      )

    assert_receive :fetch_publication_plan
    assert_receive :refresh_auth_state

    _wizard = Nav.transition(state, :wizard, app_pid: self())
    assert_receive :fetch_wizard_targets
    assert_receive :fetch_wizard_policies
  end
end
