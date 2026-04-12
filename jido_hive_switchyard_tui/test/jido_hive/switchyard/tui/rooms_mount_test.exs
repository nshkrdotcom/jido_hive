defmodule JidoHive.Switchyard.TUI.RoomsComponentTest do
  use ExUnit.Case, async: true

  alias JidoHive.Switchyard.TUI.RoomsComponent
  alias Workbench.Context

  defmodule ClientStub do
    def list_rooms(_api_base_url, _opts),
      do: [%{room_id: "room-1", brief: "Brief", status: "running"}]

    def load_room_workspace(_api_base_url, _room_id, _opts) do
      %{
        room_id: "room-1",
        objective: "Brief",
        control_plane: %{
          objective: "Brief",
          stage: "Review",
          next_action: "Inspect ctx-1",
          reason: "Open question remains",
          focus_queue: [],
          publish_ready: false,
          graph_counts: %{total: 1}
        },
        graph_sections: [
          %{title: "QUESTIONS", items: [%{context_id: "ctx-1", title: "Question"}]}
        ],
        detail_index: %{"ctx-1" => %{context_id: "ctx-1", title: "Question", body: "[no body]"}},
        selected_context_id: "ctx-1",
        selected_detail: %{context_id: "ctx-1", title: "Question", body: "[no body]"},
        conversation: [],
        events: []
      }
    end

    def load_provenance(_api_base_url, _room_id, _context_id, _opts),
      do: {:ok, %{trace: [%{depth: 0, title: "Question", via: nil}], recommended_actions: []}}

    def load_publication_workspace(_api_base_url, _room_id, _subject, _opts) do
      %{
        channels: [
          %{channel: "github", selected?: true, auth: %{status: :cached, connection_id: "conn-1"}}
        ],
        selected_channel: %{channel: "github"},
        preview_lines: ["Draft"],
        readiness: ["Selected channel: github"],
        ready?: true
      }
    end

    def submit_steering(_api_base_url, _room_id, _identity, text, _opts), do: {:ok, %{text: text}}
    def publish(_api_base_url, _room_id, _workspace, bindings, _opts), do: {:ok, bindings}
  end

  defp props(opts \\ []) do
    %{
      app: %{id: "jido-hive.rooms"},
      context:
        %{
          api_base_url: "http://127.0.0.1:4000/api",
          subject: "alice",
          participant_id: "alice",
          participant_role: "coordinator",
          authority_level: "binding",
          client_module: ClientStub
        }
        |> Map.merge(Map.new(opts))
    }
  end

  test "init loads rooms by default" do
    assert {:ok, next_state, [command]} = RoomsComponent.init(props(), %Context{})

    assert next_state.screen == :rooms
    assert command.kind == :async
  end

  test "init with room_id requests the room workspace directly" do
    assert {:ok, next_state, [command]} =
             RoomsComponent.init(props(room_id: "room-1"), %Context{})

    assert next_state.room_id == "room-1"
    assert command.kind == :async
  end

  test "maps room-specific bindings while the component is active" do
    state =
      elem(RoomsComponent.init(props(), %Context{}), 1)
      |> Map.put(:screen, :room)

    bindings = RoomsComponent.keymap(state, props(), %Context{})

    assert :open_publish ==
             Workbench.Keymap.match_event(
               bindings,
               %ExRatatui.Event.Key{code: "p", modifiers: ["ctrl"]}
             )
  end
end
