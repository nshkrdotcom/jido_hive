defmodule JidoHive.Switchyard.TUIRuntimeSmokeTest do
  use ExUnit.Case, async: false

  alias ExRatatui.Runtime
  alias JidoHive.Switchyard.Site
  alias JidoHive.Switchyard.TUI.RoomsComponent
  alias JidoHive.Switchyard.TUI.State, as: RoomsState
  alias Switchyard.Site.Local
  alias Switchyard.TUI.App

  @agent_name __MODULE__.AgentState

  def agent_name, do: @agent_name

  def record_call(call) do
    Agent.update(agent_name(), fn state ->
      %{state | calls: [call | state.calls]}
    end)
  end

  def record_submission(text) do
    Agent.update(agent_name(), fn state ->
      %{
        state
        | calls: [{:submit_steering, text} | state.calls],
          submissions: state.submissions ++ [text]
      }
    end)
  end

  def record_publish(room_id, workspace, bindings) do
    Agent.update(agent_name(), fn state ->
      %{
        state
        | calls: [{:publish, room_id, bindings} | state.calls],
          published: %{room_id: room_id, workspace: workspace, bindings: bindings}
      }
    end)
  end

  def calls do
    Agent.get(agent_name(), &Enum.reverse(&1.calls))
  end

  def submissions do
    Agent.get(agent_name(), & &1.submissions)
  end

  def published do
    Agent.get(agent_name(), & &1.published)
  end

  def room_workspace(room_id) do
    submissions = submissions()

    %{
      room_id: room_id,
      objective: "Review Switchyard integration",
      control_plane: %{
        objective: "Review Switchyard integration",
        stage: "Review",
        next_action: "Inspect ctx-1",
        reason: "Validate the current Switchyard-backed TUI flow",
        focus_queue: [
          %{kind: "question", title: "Smoke the current room flow", action: "open workspace"}
        ],
        publish_ready: true,
        graph_counts: %{total: 2}
      },
      graph_sections: [
        %{
          title: "QUESTIONS",
          items: [
            %{
              context_id: "ctx-1",
              title: "Smoke the current room flow",
              selected?: true,
              graph: %{incoming: 1, outgoing: 1},
              flags: %{binding: false, conflict: false, stale: false, duplicate_count: 0}
            }
          ]
        },
        %{
          title: "EVIDENCE",
          items: [
            %{
              context_id: "ctx-2",
              title: "Switchyard runtime boots in test_mode",
              selected?: false,
              graph: %{incoming: 1, outgoing: 0},
              flags: %{binding: false, conflict: false, stale: false, duplicate_count: 0}
            }
          ]
        }
      ],
      detail_index: %{
        "ctx-1" =>
          detail(
            "ctx-1",
            "question",
            "Smoke the current room flow",
            "Open the room and exercise the publish overlay."
          ),
        "ctx-2" =>
          detail(
            "ctx-2",
            "evidence",
            "Switchyard runtime boots in test_mode",
            "The TUI should render headlessly and accept injected key events."
          )
      },
      selected_context_id: "ctx-1",
      selected_detail:
        detail(
          "ctx-1",
          "question",
          "Smoke the current room flow",
          "Open the room and exercise the publish overlay."
        ),
      conversation:
        Enum.map(submissions, fn text ->
          %{participant_id: "alice", body: text, pending?: false}
        end),
      events:
        Enum.with_index(submissions, 1)
        |> Enum.map(fn {_text, index} ->
          %{
            kind: "contribution.submitted",
            status: "completed",
            participant_id: "alice",
            sequence: index
          }
        end)
    }
  end

  defp detail(context_id, object_type, title, body) do
    %{
      context_id: context_id,
      object_type: object_type,
      title: title,
      body: body,
      graph: %{incoming: 1, outgoing: 1},
      recommended_actions: [%{shortcut: "ctrl+p", label: "Open publish"}]
    }
  end

  defmodule ClientStub do
    alias JidoHive.Switchyard.TUIRuntimeSmokeTest, as: SmokeTest

    def list_rooms(_api_base_url, _opts) do
      SmokeTest.record_call(:list_rooms)

      [
        %{
          id: "room-1",
          name: "Switchyard smoke room",
          status: "running",
          completed_slots: 1,
          total_slots: 2
        }
      ]
    end

    def load_room_workspace(_api_base_url, room_id, _opts) do
      SmokeTest.record_call({:load_room_workspace, room_id})
      SmokeTest.room_workspace(room_id)
    end

    def load_provenance(_api_base_url, room_id, context_id, _opts) do
      SmokeTest.record_call({:load_provenance, room_id, context_id})

      {:ok,
       %{
         trace: [%{depth: 0, title: "Smoke the current room flow", via: nil}],
         recommended_actions: [%{shortcut: "ctrl+p", label: "Publish"}]
       }}
    end

    def submit_steering(_api_base_url, room_id, identity, text, _opts) do
      SmokeTest.record_call({:submit_identity, room_id, identity})
      SmokeTest.record_submission(text)
      {:ok, %{text: text}}
    end
  end

  defmodule PublicationsStub do
    alias JidoHive.Switchyard.TUIRuntimeSmokeTest, as: SmokeTest

    def load_publication_workspace(_api_base_url, room_id, subject, _opts) do
      SmokeTest.record_call({:load_publication_workspace, room_id, subject})

      %{
        channels: [
          %{
            channel: "github",
            selected?: true,
            auth: %{status: :cached, connection_id: "conn-1"},
            required_bindings: [%{field: "repo", label: "Repository"}]
          }
        ],
        selected_channel: %{
          channel: "github",
          required_bindings: [%{field: "repo", label: "Repository"}]
        },
        preview_lines: ["Preview the room review before publishing."],
        readiness: ["Selected channel: github"],
        ready?: true
      }
    end

    def publish(_api_base_url, room_id, workspace, bindings, _opts) do
      SmokeTest.record_publish(room_id, workspace, bindings)
      {:ok, %{room_id: room_id, bindings: bindings}}
    end
  end

  setup do
    start_supervised!(%{
      id: agent_name(),
      start:
        {Agent, :start_link,
         [fn -> %{calls: [], submissions: [], published: nil} end, [name: agent_name()]]}
    })

    :ok
  end

  test "boots the live Switchyard runtime and completes a headless room workflow" do
    {:ok, pid} =
      App.start_link(
        name: nil,
        test_mode: {110, 32},
        site_modules: [Local, Site],
        open_app: RoomsComponent.app_id(),
        api_base_url: "http://127.0.0.1:4000/api",
        subject: "alice",
        participant_id: "alice",
        participant_role: "coordinator",
        client_module: ClientStub,
        publications_module: PublicationsStub
      )

    ref = Process.monitor(pid)

    on_exit(fn ->
      if Process.alive?(pid) do
        send(pid, :quit)
      end
    end)

    wait_until(fn ->
      snapshot = Runtime.snapshot(pid)
      snapshot.polling_enabled? == false and snapshot.render_count > 0
    end)

    wait_until(fn ->
      root_state(pid).shell.route == :app and
        root_state(pid).shell.selected_app_id == RoomsComponent.app_id() and
        component_state(pid).screen == :rooms and
        length(component_state(pid).rooms) == 1
    end)

    assert :list_rooms in calls()

    assert :ok = Runtime.inject_event(pid, key_event("enter"))

    wait_until(fn ->
      component_state(pid).screen == :room and
        component_state(pid).room_id == "room-1" and
        component_state(pid).selected_context_id == "ctx-1"
    end)

    assert {:load_room_workspace, "room-1"} in calls()

    assert :ok = Runtime.inject_event(pid, key_event("h"))
    assert :ok = Runtime.inject_event(pid, key_event("i"))
    assert :ok = Runtime.inject_event(pid, key_event("enter"))

    wait_until(fn -> submissions() == ["hi"] end)
    wait_until(fn -> component_state(pid).draft == "" end)

    assert :ok = Runtime.inject_event(pid, key_event("p", ["ctrl"]))

    wait_until(fn ->
      match?(%{kind: :publish}, component_state(pid).overlay)
    end)

    assert :ok = Runtime.inject_event(pid, key_event("r"))
    assert :ok = Runtime.inject_event(pid, key_event("e"))
    assert :ok = Runtime.inject_event(pid, key_event("p"))
    assert :ok = Runtime.inject_event(pid, key_event("o"))

    wait_until(fn ->
      get_in(component_state(pid).publish_bindings, ["github", "repo"]) == "repo"
    end)

    assert :ok = Runtime.inject_event(pid, key_event("enter"))

    wait_until(fn ->
      published() == %{
        room_id: "room-1",
        workspace: %{
          channels: [
            %{
              channel: "github",
              selected?: true,
              auth: %{status: :cached, connection_id: "conn-1"},
              required_bindings: [%{field: "repo", label: "Repository"}]
            }
          ],
          selected_channel: %{
            channel: "github",
            required_bindings: [%{field: "repo", label: "Repository"}]
          },
          preview_lines: ["Preview the room review before publishing."],
          readiness: ["Selected channel: github"],
          ready?: true
        },
        bindings: %{"github" => %{"repo" => "repo"}}
      }
    end)

    wait_until(fn -> is_nil(component_state(pid).overlay) end)

    assert :ok = Runtime.inject_event(pid, key_event("q", ["ctrl"]))

    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
  end

  defp root_state(pid) do
    pid
    |> runtime_state()
    |> Map.fetch!(:root_state)
  end

  defp component_state(pid) do
    pid
    |> runtime_state()
    |> Map.fetch!(:component_registry)
    |> Enum.find_value(fn
      {_path, %{module: RoomsComponent, state: state}} -> state
      _other -> nil
    end)
    |> case do
      nil -> RoomsState.new()
      state -> state
    end
  end

  defp runtime_state(pid) do
    pid
    |> :sys.get_state()
    |> Map.fetch!(:user_state)
  end

  defp wait_until(fun, timeout_ms \\ 1_000)

  defp wait_until(fun, timeout_ms) when timeout_ms <= 0 do
    assert fun.()
  end

  defp wait_until(fun, timeout_ms) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      wait_until(fun, timeout_ms - 20)
    end
  end

  defp key_event(code, modifiers \\ []) do
    struct(Module.concat([ExRatatui.Event, Key]), code: code, kind: "press", modifiers: modifiers)
  end
end
