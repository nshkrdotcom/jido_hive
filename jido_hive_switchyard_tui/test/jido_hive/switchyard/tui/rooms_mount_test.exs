defmodule JidoHive.Switchyard.TUI.RoomsMountTest do
  use ExUnit.Case, async: true

  alias JidoHive.Switchyard.TUI.RoomsMount
  alias Switchyard.TUI.Model

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

  defp mount_state do
    RoomsMount.init(client_module: ClientStub)
  end

  defp room_mount_state do
    %{mount_state() | screen: :room}
  end

  defp model(opts \\ []) do
    Model.new(
      shell: %{
        Model.new().shell
        | route: :app,
          selected_site_id: "jido-hive",
          selected_app_id: "jido-hive.rooms"
      },
      context:
        %{
          api_base_url: "http://127.0.0.1:4000/api",
          subject: "alice",
          participant_id: "alice",
          participant_role: "coordinator",
          authority_level: "binding"
        }
        |> Map.merge(Map.new(opts))
    )
  end

  test "open loads rooms by default" do
    {_next_model, next_state, [command]} = RoomsMount.open(model(), mount_state())

    assert next_state.screen == :rooms
    assert command.kind == :async
  end

  test "open with room_id requests the room workspace directly" do
    {_next_model, next_state, [command]} =
      RoomsMount.open(model(room_id: "room-1"), mount_state())

    assert next_state.room_id == "room-1"
    assert command.kind == :async
  end

  test "maps room-specific keys while the mount is active" do
    assert {:msg, :open_publish} =
             RoomsMount.event_to_msg(
               %ExRatatui.Event.Key{code: "p", modifiers: ["ctrl"]},
               model(),
               room_mount_state()
             )
  end
end
