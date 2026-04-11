defmodule JidoHiveWebWeb.Support.RoomsStub do
  @moduledoc false

  def list_rooms(api_base_url, opts), do: list(api_base_url, opts)

  def list(_api_base_url, _opts) do
    [
      %{
        room_id: "room-1",
        brief: "Stabilize auth path",
        status: "running",
        completed_slots: 1,
        total_slots: 2,
        participant_count: 2,
        flagged: false,
        fetch_error: false
      }
    ]
  end

  def load_room_workspace(_api_base_url, room_id, _opts), do: workspace(room_id)
  def workspace(_api_base_url, room_id, _opts), do: workspace(room_id)

  def load_provenance(api_base_url, room_id, context_id, opts),
    do: provenance(api_base_url, room_id, context_id, opts)

  def provenance(_api_base_url, _room_id, "ctx-1", _opts) do
    {:ok,
     %{
       context_id: "ctx-1",
       title: "Question",
       recommended_actions: [%{label: "Send clarification", shortcut: "Enter"}],
       trace: [%{depth: 0, title: "Question", via: nil}]
     }}
  end

  def create_room(_api_base_url, payload, _opts) do
    send(test_pid(), {:create_room, payload})
    {:ok, payload}
  end

  def normalize_create_attrs(attrs), do: JidoHiveSurface.normalize_create_attrs(attrs)

  def run_room(_api_base_url, room_id, opts) do
    send(test_pid(), {:run_room, room_id, opts})
    {:ok, %{"operation_id" => "run-1", "status" => "queued"}}
  end

  def room_run_status(_api_base_url, _room_id, _operation_id, _opts) do
    {:ok, %{"operation_id" => "run-1", "status" => "completed"}}
  end

  def normalize_run_attrs(attrs), do: JidoHiveSurface.normalize_run_attrs(attrs)

  defp workspace(room_id) do
    %{
      room_id: room_id,
      objective: "Stabilize auth path",
      control_plane: %{
        objective: "Stabilize auth path",
        stage: "Review",
        next_action: "Inspect contradiction",
        reason: "Open question remains",
        focus_queue: [
          %{context_id: "ctx-1", title: "Question", why: "Operator review recommended"}
        ],
        publish_ready: false,
        publish_blockers: ["Question unresolved"],
        blockers: [],
        graph_counts: %{total: 1}
      },
      graph_sections: [
        %{
          title: "OPEN QUESTIONS",
          items: [
            %{
              context_id: "ctx-1",
              title: "Question",
              graph: %{incoming: 0, outgoing: 0},
              flags: %{binding: false, conflict: false, stale: false, duplicate_count: 0}
            }
          ]
        }
      ],
      detail_index: %{
        "ctx-1" => %{
          context_id: "ctx-1",
          title: "Question",
          body: "Need clarification",
          recommended_actions: [%{label: "Inspect provenance", shortcut: "Ctrl+E"}]
        }
      },
      selected_context_id: "ctx-1",
      selected_detail: %{
        context_id: "ctx-1",
        title: "Question",
        body: "Need clarification",
        recommended_actions: [%{label: "Inspect provenance", shortcut: "Ctrl+E"}]
      },
      conversation: [
        %{participant_id: "alice", contribution_type: "chat", body: "hello", pending?: false}
      ],
      events: [%{body: "event", kind: "event", status: "completed"}]
    }
  end

  defp test_pid do
    Application.get_env(:jido_hive_web, :test_pid)
  end
end

defmodule JidoHiveWebWeb.Support.PublicationsStub do
  @moduledoc false

  def load_publication_workspace(_api_base_url, _room_id, _subject, _opts), do: workspace()
  def workspace(_api_base_url, _room_id, _subject, _opts), do: workspace()

  def publish(_api_base_url, room_id, _workspace, bindings, _opts) do
    payload = %{
      "channels" => ["github"],
      "bindings" => bindings
    }

    send(test_pid(), {:publish_room, room_id, payload})
    {:ok, payload}
  end

  defp workspace do
    %{
      duplicate_policy: "canonical_only",
      source_entries: ["decision"],
      channels: [
        %{
          channel: "github",
          selected?: true,
          auth: %{status: :cached, connection_id: "conn-1"},
          required_bindings: [%{field: "repo", description: "Repository name"}],
          draft: %{"title" => "Draft", "body" => "Body"}
        }
      ],
      selected_channel: %{
        channel: "github",
        required_bindings: [%{field: "repo", description: "Repository name"}],
        draft: %{"title" => "Draft", "body" => "Body"}
      },
      preview_lines: ["Draft", "Body"],
      readiness: ["Selected channel: github"],
      ready?: true
    }
  end

  defp test_pid do
    Application.get_env(:jido_hive_web, :test_pid)
  end
end

defmodule JidoHiveWebWeb.Support.RoomSessionStub do
  @moduledoc false

  def start_link(opts) do
    send(test_pid(), {:room_session_start, opts})
    {:ok, :session}
  end

  def subscribe(:session) do
    send(self(), {:room_session_snapshot, "room-1", snapshot()})
    :ok
  end

  def refresh(:session) do
    send(self(), {:room_session_snapshot, "room-1", snapshot()})
    {:ok, snapshot()}
  end

  def submit_chat(:session, %{text: text}) do
    send(test_pid(), {:submit_chat, text})
    send(self(), {:room_session_snapshot, "room-1", snapshot(text)})
    {:ok, %{text: text}}
  end

  def shutdown(:session), do: :ok

  defp snapshot(latest_text \\ nil) do
    %{
      "room_id" => "room-1",
      "brief" => "Stabilize auth path",
      "status" => "running",
      "workflow_summary" => %{
        "objective" => "Stabilize auth path",
        "stage" => "Review",
        "next_action" => "Inspect contradiction",
        "publish_ready" => false,
        "publish_blockers" => ["Question unresolved"],
        "blockers" => [],
        "graph_counts" => %{"total" => 1},
        "focus_candidates" => []
      },
      "timeline" => [%{"kind" => "event", "body" => "event", "status" => "completed"}],
      "context_objects" => [
        %{
          "context_id" => "ctx-1",
          "object_type" => "question",
          "title" => "Question",
          "body" => "Need clarification",
          "relations" => []
        }
      ],
      "contributions" =>
        Enum.reject(
          [
            %{"participant_id" => "alice", "contribution_type" => "chat", "body" => "hello"},
            latest_contribution(latest_text)
          ],
          &is_nil/1
        ),
      "operations" => []
    }
  end

  defp latest_contribution(nil), do: nil

  defp latest_contribution(text) do
    %{"participant_id" => "alice", "contribution_type" => "chat", "body" => text}
  end

  defp test_pid do
    Application.get_env(:jido_hive_web, :test_pid)
  end
end
