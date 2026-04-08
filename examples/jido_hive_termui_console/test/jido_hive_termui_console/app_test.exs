defmodule JidoHiveTermuiConsole.AppTest do
  use ExUnit.Case, async: false

  alias ExRatatui.Event.Key
  alias JidoHiveTermuiConsole.{App, Model, TestSupport}

  defmodule HTTPStub do
    def get(_base, _path) do
      {:ok,
       %{
         "data" => %{
           "room_id" => "room-1",
           "status" => "running",
           "dispatch_state" => %{"completed_slots" => 0, "total_slots" => 2},
           "participants" => []
         }
       }}
    end
  end

  defmodule EmbeddedStub do
    def start_link(_opts) do
      Agent.start_link(fn ->
        %{
          snapshot: %{
            "timeline" => [],
            "context_objects" => [],
            "last_error" => nil
          },
          submitted: nil
        }
      end)
    end

    def snapshot(server), do: Agent.get(server, & &1.snapshot)
    def refresh(server), do: {:ok, snapshot(server)}

    def submit_chat(server, attrs) do
      Agent.update(server, &Map.put(&1, :submitted, attrs))
      {:ok, %{"summary" => Map.get(attrs, :text) || Map.get(attrs, "text")}}
    end

    def accept_context(_server, _context_id, _attrs), do: {:ok, %{"authority_level" => "binding"}}
  end

  defmodule PollerStub do
    def start_link(_opts), do: {:ok, spawn(fn -> Process.sleep(:infinity) end)}
  end

  defmodule ConfigStub do
    def add_room(room_id, api_base_url) do
      send(test_pid(), {:add_room, room_id, api_base_url})
      :ok
    end

    def list_rooms(_api_base_url), do: []

    defp test_pid do
      Application.fetch_env!(:jido_hive_termui_console, :app_test_pid)
    end
  end

  defmodule WizardHTTPStub do
    def get(_base, "/rooms/" <> room_id) do
      {:ok,
       %{
         "data" => %{
           "room_id" => room_id,
           "status" => "running",
           "dispatch_state" => %{"completed_slots" => 0, "total_slots" => 3},
           "participants" => []
         }
       }}
    end

    def post(_base, "/rooms", payload) do
      send(test_pid(), {:http_post, "/rooms", payload})
      {:ok, %{"data" => %{"room_id" => payload["room_id"], "status" => "idle"}}}
    end

    def post(_base, path, payload) do
      send(test_pid(), {:http_post, path, payload})
      {:ok, %{"data" => %{"status" => "publication_ready"}}}
    end

    defp test_pid do
      Application.fetch_env!(:jido_hive_termui_console, :app_test_pid)
    end
  end

  defmodule PublishHTTPStub do
    def get(_base, "/rooms/room-1") do
      {:ok,
       %{
         "data" => %{
           "room_id" => "room-1",
           "status" => "publication_ready",
           "dispatch_state" => %{"completed_slots" => 6, "total_slots" => 6},
           "participants" => []
         }
       }}
    end

    def get(_base, "/rooms/room-1/publication_plan") do
      {:ok,
       %{
         "data" => %{
           "publications" => [
             %{
               "channel" => "github",
               "required_bindings" => [
                 %{"field" => "repo", "description" => "Repository to publish into."}
               ]
             }
           ]
         }
       }}
    end

    def get(_base, "/connectors/github/connections?subject=alice") do
      {:ok,
       %{
         "data" => [
           %{
             "connection_id" => "connection-12",
             "state" => "connected",
             "updated_at" => "2026-04-08T21:44:31Z"
           }
         ]
       }}
    end

    def get(_base, "/connectors/notion/connections?subject=alice"), do: {:ok, %{"data" => []}}

    def post(_base, "/rooms/room-1/publications", payload) do
      send(test_pid(), {:publish_payload, payload})
      {:ok, %{"data" => %{"status" => "submitted"}}}
    end

    def post(_base, path, payload) do
      send(test_pid(), {:http_post, path, payload})
      {:ok, %{"data" => %{"status" => "ok"}}}
    end

    defp test_pid do
      Application.fetch_env!(:jido_hive_termui_console, :app_test_pid)
    end
  end

  setup do
    Application.put_env(:jido_hive_termui_console, :app_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:jido_hive_termui_console, :app_test_pid)
    end)

    snapshot = %{
      "timeline" => [],
      "context_objects" => [
        %{
          "context_id" => "ctx-1",
          "object_type" => "belief",
          "title" => "Root hypothesis"
        }
      ]
    }

    {:ok, embedded} = Agent.start_link(fn -> %{snapshot: snapshot, submitted: nil} end)

    model =
      Model.new(
        embedded: embedded,
        embedded_module: EmbeddedStub,
        http_module: HTTPStub,
        room_id: "room-1",
        participant_id: "alice",
        authority_level: "binding",
        snapshot: snapshot
      )
      |> Map.put(:active_screen, :room)

    %{embedded: embedded, model: model}
  end

  test "room enter submits plain chat when relation mode is none", %{
    embedded: embedded,
    model: model
  } do
    state = %{model | input_buffer: "plain update", relation_mode: :none}

    {next_state, []} = App.update(:room_enter, state)

    assert next_state.input_buffer == ""

    assert Agent.get(embedded, & &1.submitted) == %{
             text: "plain update",
             authority_level: "binding",
             participant_id: "alice",
             participant_role: "coordinator"
           }
  end

  test "room enter submits selected relation context with binding authority", %{
    embedded: embedded,
    model: model
  } do
    state = %{model | input_buffer: "I think auth is broken", relation_mode: :supports}

    {next_state, []} = App.update(:room_enter, state)

    assert next_state.input_buffer == ""

    assert Agent.get(embedded, & &1.submitted) == %{
             text: "I think auth is broken",
             selected_context_id: "ctx-1",
             selected_context_object_type: "belief",
             selected_relation: "supports",
             authority_level: "binding",
             participant_id: "alice",
             participant_role: "coordinator"
           }
  end

  test "room view renders without crashing across width breakpoints", %{model: model} do
    render_text =
      [80, 120, 200]
      |> Enum.map(fn width ->
        model
        |> Map.put(:screen_width, width)
        |> App.view()
        |> TestSupport.collect_text()
        |> Enum.join("\n")
      end)

    assert Enum.all?(render_text, &String.contains?(&1, "Room room-1"))
  end

  test "room enter opens conflict for incoming contradict relations", %{model: model} do
    snapshot = %{
      "timeline" => [],
      "context_objects" => [
        %{
          "context_id" => "ctx-1",
          "object_type" => "decision",
          "title" => "Base claim"
        },
        %{
          "context_id" => "ctx-2",
          "object_type" => "note",
          "title" => "Conflict probe",
          "relations" => [%{"relation" => "contradicts", "target_id" => "ctx-1"}]
        }
      ]
    }

    state = %{model | snapshot: snapshot, input_buffer: ""}

    {next_state, []} = App.update(:room_enter, state)

    assert next_state.active_screen == :conflict
    assert next_state.conflict_left["context_id"] == "ctx-1"
    assert next_state.conflict_right["context_id"] == "ctx-2"
  end

  test "room guide copy renders when help is visible", %{model: model} do
    render_text =
      model
      |> Map.put(:help_visible, true)
      |> App.view()
      |> TestSupport.collect_text()
      |> Enum.join("\n")

    assert render_text =~ "Room Guide"
    assert render_text =~ "including q"
    assert render_text =~ "edit the draft"
    assert render_text =~ "Ctrl+Q quits"
  end

  test "room guide swallows normal typing until dismissed", %{model: model} do
    state = %{model | help_visible: true}

    assert App.event_to_msg(%Key{code: "q", kind: "press"}, state) == :ignore

    assert App.event_to_msg(%Key{code: "g", kind: "press", modifiers: ["ctrl"]}, state) ==
             {:msg, :dismiss_help}
  end

  test "event log updates append formatted lines", %{model: model} do
    assert {:noreply, next_state} =
             App.handle_info(
               {:event_log_update, [%{"kind" => "contribution.recorded", "cursor" => "c1"}],
                "c1"},
               model
             )

    assert next_state.event_log_cursor == "c1"
    assert next_state.event_log_lines == ["contribution.recorded"]
  end

  test "wizard view renders phase maps without crashing" do
    model =
      Model.new([])
      |> Map.put(:active_screen, :wizard)
      |> Map.put(:wizard_step, 2)
      |> Map.put(:wizard_fields, %{
        "phases" => [
          %{
            "phase" => "analysis",
            "objective" => "Analyze the brief and add room-scoped context.",
            "allowed_contribution_types" => ["reasoning"]
          }
        ]
      })

    render_text =
      model
      |> App.view()
      |> TestSupport.collect_text()
      |> Enum.join("\n")

    assert render_text =~ "Phases from selected policy:"
    assert render_text =~ "analysis"
    assert render_text =~ "Analyze the brief and add room-scoped context."
  end

  test "wizard view distinguishes empty worker list from loading" do
    loading_text =
      Model.new([])
      |> Map.put(:active_screen, :wizard)
      |> Map.put(:wizard_step, 3)
      |> Map.put(:wizard_targets_state, :loading)
      |> App.view()
      |> TestSupport.collect_text()
      |> Enum.join("\n")

    ready_text =
      Model.new([])
      |> Map.put(:active_screen, :wizard)
      |> Map.put(:wizard_step, 3)
      |> Map.put(:wizard_targets_state, :ready)
      |> Map.put(:wizard_available_targets, [])
      |> App.view()
      |> TestSupport.collect_text()
      |> Enum.join("\n")

    assert loading_text =~ "Loading targets..."
    assert ready_text =~ "No worker targets available on this server."
    assert ready_text =~ "bin/hive-clients"
  end

  test "wizard submit workers reports no available targets" do
    model =
      Model.new([])
      |> Map.put(:active_screen, :wizard)
      |> Map.put(:wizard_step, 3)
      |> Map.put(:wizard_targets_state, :ready)
      |> Map.put(:wizard_available_targets, [])

    {next_state, []} = App.update(:wizard_enter, model)

    assert next_state.status_line == "No worker targets available on this server"
    assert next_state.status_severity == :warn
  end

  test "wizard submit workers clears stale warning on confirm step" do
    model =
      Model.new([])
      |> Map.put(:active_screen, :wizard)
      |> Map.put(:wizard_step, 3)
      |> Map.put(:status_line, "Select at least one worker")
      |> Map.put(:status_severity, :error)
      |> Map.put(:wizard_fields, %{
        "participants" => [
          %{
            "participant_id" => "worker-01",
            "target_id" => "target-01",
            "capability_id" => "codex.exec.session"
          }
        ]
      })

    {next_state, []} = App.update(:wizard_enter, model)

    assert next_state.wizard_step == 4
    assert next_state.status_line == "Press Enter to create and start the room"
    assert next_state.status_severity == :info
  end

  test "wizard create room transitions immediately and runs room in background" do
    model =
      Model.new(
        http_module: WizardHTTPStub,
        config_module: ConfigStub,
        embedded_module: EmbeddedStub,
        event_log_poller_module: PollerStub
      )
      |> Map.put(:active_screen, :wizard)
      |> Map.put(:wizard_step, 4)
      |> Map.put(:wizard_fields, %{
        "brief" => "Develop specs for debugging term ui",
        "dispatch_policy_id" => "round_robin/v2",
        "phases" => [%{"phase" => "analysis"}],
        "participants" => [
          %{
            "participant_id" => "worker-01",
            "participant_role" => "worker",
            "provider" => "test",
            "target_id" => "target-01",
            "capability_id" => "codex.exec.session"
          }
        ]
      })

    {next_state, []} = App.update(:wizard_enter, model)

    assert next_state.active_screen == :room
    assert next_state.status_line =~ "run started in background"
    assert_receive {:http_post, "/rooms", payload}
    assert payload["dispatch_policy_id"] == "round_robin/v2"
    assert_receive {:add_room, room_id, "http://127.0.0.1:4000/api"}
    assert room_id == next_state.room_id
    assert_receive {:http_post, path, %{}}
    assert path == "/rooms/#{URI.encode_www_form(room_id)}/run"
  end

  test "refresh_auth_state loads server-backed publish auth for the current participant" do
    state =
      Model.new(
        http_module: PublishHTTPStub,
        room_id: "room-1",
        participant_id: "alice"
      )
      |> Map.put(:active_screen, :publish)

    {next_state, []} = App.handle_message(:refresh_auth_state, state)

    assert next_state.publish_auth_state == %{
             "github" => %{
               connection_id: "connection-12",
               source: :server,
               state: "connected",
               status: :cached
             },
             "notion" => %{
               connection_id: nil,
               source: :server,
               state: nil,
               status: :missing
             }
           }
  end

  test "publish_submit sends server-backed connection ids" do
    state =
      Model.new(
        http_module: PublishHTTPStub,
        room_id: "room-1",
        participant_id: "alice"
      )
      |> Map.put(:active_screen, :publish)
      |> Map.put(:snapshot, %{"timeline" => [], "context_objects" => []})
      |> Map.put(:publish_plan, %{
        "publications" => [
          %{
            "channel" => "github",
            "required_bindings" => [
              %{"field" => "repo", "description" => "Repository to publish into."}
            ]
          }
        ]
      })
      |> Map.put(:publish_selected, ["github"])
      |> Map.put(:publish_bindings, %{"github" => %{"repo" => "nshkrdotcom/cluster_test"}})
      |> Map.put(:publish_auth_state, %{
        "github" => %{
          connection_id: "connection-12",
          source: :server,
          state: "connected",
          status: :cached
        },
        "notion" => %{
          connection_id: nil,
          source: :server,
          state: nil,
          status: :missing
        }
      })

    {next_state, []} = App.update(:publish_submit, state)

    assert_receive {:publish_payload, payload}
    assert payload["channels"] == ["github"]
    assert payload["bindings"] == %{"github" => %{"repo" => "nshkrdotcom/cluster_test"}}
    assert payload["connections"] == %{"github" => "connection-12"}
    assert payload["tenant_id"] == "workspace-local"
    assert payload["actor_id"] == "operator-1"
    assert next_state.status_line == "Publication submitted"
    assert next_state.status_severity == :info
  end
end
