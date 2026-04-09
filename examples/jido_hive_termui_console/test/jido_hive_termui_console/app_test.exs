defmodule JidoHiveTermuiConsole.AppTest do
  use ExUnit.Case, async: false

  alias ExRatatui.Event.Key
  alias JidoHiveTermuiConsole.{App, Model, TestSupport}

  defmodule OperatorStub do
    def fetch_room(_base, _room_id, _opts \\ []) do
      {:ok,
       %{
         "room_id" => "room-1",
         "status" => "running",
         "dispatch_state" => %{"completed_slots" => 0, "total_slots" => 2},
         "participants" => []
       }}
    end

    def list_saved_rooms(_api_base_url), do: []
  end

  defmodule EmbeddedStub do
    def start_link(_opts) do
      Agent.start_link(fn ->
        %{
          snapshot: %{
            "room_id" => "room-1",
            "status" => "running",
            "dispatch_state" => %{"completed_slots" => 0, "total_slots" => 2},
            "participants" => [],
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
    def subscribe(server), do: send(test_pid(), {:embedded_subscribe, server})

    def submit_chat(server, attrs) do
      Agent.update(server, &Map.put(&1, :submitted, attrs))
      send(test_pid(), {:embedded_submit_chat, attrs})
      {:ok, %{"summary" => Map.get(attrs, :text) || Map.get(attrs, "text")}}
    end

    def submit_chat_async(server, attrs) do
      operation_id = Map.get(attrs, :operation_id) || Map.get(attrs, "operation_id")

      Agent.update(server, fn state ->
        snapshot =
          state.snapshot
          |> Map.put(
            "operations",
            [
              %{
                "operation_id" => operation_id,
                "status" => "completed",
                "type" => "room_submit"
              }
            ]
          )

        state
        |> Map.put(:submitted, attrs)
        |> Map.put(:snapshot, snapshot)
      end)

      send(test_pid(), {:embedded_submit_chat, attrs})
      {:ok, %{"operation_id" => operation_id, "status" => "accepted"}}
    end

    def accept_context(_server, context_id, _attrs) do
      send(test_pid(), {:embedded_accept_context, context_id})
      {:ok, %{"authority_level" => "binding"}}
    end

    defp test_pid do
      Application.fetch_env!(:jido_hive_termui_console, :app_test_pid)
    end
  end

  defmodule PollerStub do
    def start_link(_opts), do: {:ok, spawn(fn -> Process.sleep(:infinity) end)}
  end

  defmodule WizardOperatorStub do
    def fetch_room(_base, room_id, _opts \\ []) do
      {:ok,
       %{
         "room_id" => room_id,
         "status" => "running",
         "dispatch_state" => %{"completed_slots" => 0, "total_slots" => 3},
         "participants" => []
       }}
    end

    def create_room(_base, payload) do
      send(test_pid(), {:operator_create_room, payload})
      {:ok, %{"room_id" => payload["room_id"], "status" => "idle"}}
    end

    def add_saved_room(room_id, api_base_url) do
      send(test_pid(), {:add_room, room_id, api_base_url})
      :ok
    end

    def start_room_run_operation(_base, room_id, opts) do
      send(test_pid(), {:operator_start_room_run_operation, room_id, opts})

      {:ok,
       %{
         "operation_id" => "server-room-run-op-1",
         "client_operation_id" => Keyword.fetch!(opts, :client_operation_id),
         "status" => "accepted"
       }}
    end

    def list_targets(_base), do: {:ok, []}
    def list_policies(_base), do: {:ok, []}
    def list_saved_rooms(_api_base_url), do: []

    defp test_pid do
      Application.fetch_env!(:jido_hive_termui_console, :app_test_pid)
    end
  end

  defmodule RunTimeoutOperatorStub do
    def fetch_room(_base, "room-1", _opts \\ []) do
      {:ok,
       %{
         "room_id" => "room-1",
         "status" => "idle",
         "dispatch_state" => %{"completed_slots" => 0, "total_slots" => 6},
         "participants" => []
       }}
    end
  end

  defmodule PublishOperatorStub do
    def fetch_room(_base, "room-1", _opts \\ []) do
      {:ok,
       %{
         "room_id" => "room-1",
         "status" => "publication_ready",
         "dispatch_state" => %{"completed_slots" => 6, "total_slots" => 6},
         "participants" => []
       }}
    end

    def fetch_publication_plan(_base, "room-1") do
      {:ok,
       %{
         "publications" => [
           %{
             "channel" => "github",
             "required_bindings" => [
               %{"field" => "repo", "description" => "Repository to publish into."}
             ]
           }
         ]
       }}
    end

    def load_auth_state(_base, "alice") do
      %{
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

    def publish_room(_base, "room-1", payload) do
      send(test_pid(), {:publish_payload, payload})
      {:ok, %{"status" => "submitted"}}
    end

    def connection_id(auth_state, channel) do
      get_in(auth_state, [channel, :connection_id])
    end

    def auth_status(auth_state, channel) do
      get_in(auth_state, [channel, :status]) || :missing
    end

    def list_saved_rooms(_api_base_url), do: []

    defp test_pid do
      Application.fetch_env!(:jido_hive_termui_console, :app_test_pid)
    end
  end

  defmodule EmptyRoomOperatorStub do
    def fetch_room(_base, "room-1", _opts \\ []) do
      {:ok,
       %{
         "room_id" => "room-1",
         "status" => "running",
         "dispatch_state" => %{"completed_slots" => 0, "total_slots" => 2},
         "participants" => [],
         "contributions" => [],
         "context_objects" => [],
         "timeline" => []
       }}
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
        operator_module: OperatorStub,
        room_id: "room-1",
        participant_id: "alice",
        authority_level: "binding",
        snapshot: snapshot
      )
      |> Map.put(:active_screen, :room)

    %{embedded: embedded, model: model}
  end

  test "room enter submits plain chat asynchronously when relation mode is none", %{
    embedded: embedded,
    model: model
  } do
    state = %{model | input_buffer: "plain update", relation_mode: :none}

    assert {:noreply, pending_state} = App.handle_event(%Key{code: "enter", kind: "press"}, state)

    assert pending_state.input_buffer == ""

    assert %{room_id: "room-1", text: "plain update", operation_id: operation_id} =
             pending_state.pending_room_submit

    assert pending_state.status_line =~ "Submitting chat message... op="
    assert_receive {:embedded_submit_chat, attrs}
    assert_receive {:room_submit_accepted, "room-1", "plain update", ^operation_id, {:ok, _}}

    assert %{
             text: "plain update",
             operation_id: ^operation_id,
             authority_level: "binding",
             participant_id: "alice",
             participant_role: "coordinator"
           } = attrs

    assert Agent.get(embedded, & &1.submitted) == attrs

    assert {:noreply, accepted_state} =
             App.handle_info(
               {:room_submit_accepted, "room-1", "plain update", operation_id,
                {:ok, %{"operation_id" => operation_id, "status" => "accepted"}}},
               pending_state
             )

    assert {:noreply, next_state} =
             App.handle_info(
               {:room_session_snapshot, "room-1",
                %{
                  "room_id" => "room-1",
                  "status" => "running",
                  "dispatch_state" => %{"completed_slots" => 1, "total_slots" => 2},
                  "participants" => [],
                  "timeline" => [%{"kind" => "contribution.recorded", "cursor" => "evt-1"}],
                  "context_objects" => [
                    %{
                      "context_id" => "ctx-message-1",
                      "object_type" => "message",
                      "title" => "alice said",
                      "body" => "plain update",
                      "authored_by" => %{"participant_id" => "alice"}
                    }
                  ],
                  "operations" => [
                    %{
                      "operation_id" => operation_id,
                      "status" => "completed",
                      "type" => "room_submit"
                    }
                  ]
                }},
               accepted_state
             )

    assert next_state.pending_room_submit == nil
    assert next_state.status_line == "Submitted chat message"
  end

  test "room enter submits selected relation context asynchronously with binding authority", %{
    embedded: embedded,
    model: model
  } do
    state = %{model | input_buffer: "I think auth is broken", relation_mode: :supports}

    assert {:noreply, pending_state} = App.handle_event(%Key{code: "enter", kind: "press"}, state)

    assert pending_state.input_buffer == ""

    assert %{room_id: "room-1", text: "I think auth is broken", operation_id: operation_id} =
             pending_state.pending_room_submit

    assert_receive {:embedded_submit_chat, attrs}

    assert_receive {:room_submit_accepted, "room-1", "I think auth is broken", ^operation_id,
                    {:ok, _}}

    assert %{
             text: "I think auth is broken",
             operation_id: ^operation_id,
             selected_context_id: "ctx-1",
             selected_context_object_type: "belief",
             selected_relation: "supports",
             authority_level: "binding",
             participant_id: "alice",
             participant_role: "coordinator"
           } = attrs

    assert Agent.get(embedded, & &1.submitted) == attrs

    assert {:noreply, accepted_state} =
             App.handle_info(
               {:room_submit_accepted, "room-1", "I think auth is broken", operation_id,
                {:ok, %{"operation_id" => operation_id, "status" => "accepted"}}},
               pending_state
             )

    assert {:noreply, next_state} =
             App.handle_info(
               {:room_session_snapshot, "room-1",
                %{
                  "room_id" => "room-1",
                  "status" => "running",
                  "dispatch_state" => %{"completed_slots" => 1, "total_slots" => 2},
                  "participants" => [],
                  "timeline" => [%{"kind" => "contribution.recorded", "cursor" => "evt-2"}],
                  "context_objects" => [
                    %{
                      "context_id" => "ctx-message-2",
                      "object_type" => "message",
                      "title" => "alice said",
                      "body" => "I think auth is broken",
                      "authored_by" => %{"participant_id" => "alice"}
                    }
                  ],
                  "operations" => [
                    %{
                      "operation_id" => operation_id,
                      "status" => "completed",
                      "type" => "room_submit"
                    }
                  ]
                }},
               accepted_state
             )

    assert next_state.pending_room_submit == nil
    assert next_state.status_line == "Submitted chat message"
  end

  test "room enter restores the draft when async submission fails", %{model: model} do
    failing_embedded = self()

    failing_state =
      %{
        model
        | embedded: failing_embedded,
          embedded_module: __MODULE__.FailingEmbeddedStub,
          input_buffer: "retry me"
      }

    assert {:noreply, pending_state} =
             App.handle_event(%Key{code: "enter", kind: "press"}, failing_state)

    assert pending_state.input_buffer == ""
    assert_receive {:embedded_submit_chat, %{text: "retry me"}}
    assert %{operation_id: operation_id} = pending_state.pending_room_submit

    assert_receive {:room_submit_accepted, "room-1", "retry me", ^operation_id,
                    {:error, :submit_failed}}

    assert {:noreply, next_state} =
             App.handle_info(
               {:room_submit_accepted, "room-1", "retry me", operation_id,
                {:error, :submit_failed}},
               pending_state
             )

    assert next_state.pending_room_submit == nil
    assert next_state.input_buffer == "retry me"
    assert next_state.status_severity == :error
  end

  defmodule FailingEmbeddedStub do
    def submit_chat_async(_server, attrs) do
      send(
        Application.fetch_env!(:jido_hive_termui_console, :app_test_pid),
        {:embedded_submit_chat, attrs}
      )

      {:error, :submit_failed}
    end
  end

  defmodule ExitEmbeddedStub do
    def submit_chat_async(_server, _attrs) do
      exit(:submit_timeout)
    end
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

  test "room help renders contextual workflow and key guidance when visible", %{model: model} do
    render_text =
      model
      |> Map.put(:help_visible, true)
      |> App.view()
      |> TestSupport.collect_text()
      |> Enum.join("\n")

    assert render_text =~ "Room Help"
    assert render_text =~ "CURRENT STATE"
    assert render_text =~ "Selected context: ctx-1."
    assert render_text =~ "Ctrl+D derives_from"
    assert render_text =~ "WORKFLOW"
  end

  test "room guide swallows normal typing until dismissed", %{model: model} do
    state = %{model | help_visible: true}

    assert App.event_to_msg(%Key{code: "q", kind: "press"}, state) == :ignore

    assert App.event_to_msg(%Key{code: "enter", kind: "press"}, state) ==
             {:msg, :dismiss_help}

    assert App.event_to_msg(%Key{code: "g", kind: "press", modifiers: ["ctrl"]}, state) ==
             {:msg, :dismiss_help}

    assert App.event_to_msg(%Key{code: "f2", kind: "press"}, state) ==
             {:msg, :toggle_debug}
  end

  test "global Ctrl+C quits and F2 toggles debug mode", %{model: model} do
    assert App.event_to_msg(%Key{code: "c", kind: "press", modifiers: ["ctrl"]}, model) ==
             {:msg, :quit}

    assert App.event_to_msg(%Key{code: "f2", kind: "press"}, model) ==
             {:msg, :toggle_debug}
  end

  test "debug popup swallows normal typing until dismissed", %{model: model} do
    state = %{model | debug_visible: true}

    assert App.event_to_msg(%Key{code: "q", kind: "press"}, state) == :ignore

    assert App.event_to_msg(%Key{code: "f2", kind: "press"}, state) ==
             {:msg, :dismiss_debug}
  end

  test "Ctrl+D remains available for derives_from relation mode in the room", %{model: model} do
    assert App.event_to_msg(%Key{code: "d", kind: "press", modifiers: ["ctrl"]}, model) ==
             {:msg, {:set_relation_mode, :derives_from}}
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

  test "room-session snapshot clears stale pending chat submission when the room snapshot already contains it",
       %{model: model} do
    state =
      %{
        model
        | pending_room_submit: %{
            room_id: "room-1",
            text: "stale but accepted",
            operation_id: "room_submit-stale"
          },
          status_line: "Submitting chat message... op=room_submit-stale"
      }

    assert {:noreply, next_state} =
             App.handle_info(
               {:room_session_snapshot, "room-1",
                %{
                  "room_id" => "room-1",
                  "status" => "running",
                  "dispatch_state" => %{"completed_slots" => 1, "total_slots" => 2},
                  "participants" => [],
                  "context_objects" => [
                    %{
                      "context_id" => "ctx-message-1",
                      "object_type" => "message",
                      "title" => "alice said",
                      "body" => "stale but accepted",
                      "authored_by" => %{"participant_id" => "alice"}
                    }
                  ],
                  "timeline" => []
                }},
               state
             )

    assert next_state.pending_room_submit == nil
    assert next_state.status_line == "Submitted chat message"
    assert next_state.status_severity == :info

    assert [
             %{
               "context_id" => "ctx-message-1",
               "body" => "stale but accepted"
             }
           ] = next_state.snapshot["context_objects"]
  end

  test "room-session snapshot updates room state and event log without a timer pull", %{
    model: model
  } do
    state =
      %{
        model
        | snapshot: %{
            "room_id" => "room-1",
            "status" => "idle",
            "dispatch_state" => %{"completed_slots" => 0, "total_slots" => 6},
            "participants" => [],
            "context_objects" => [],
            "timeline" => []
          },
          event_log_lines: []
      }

    assert {:noreply, next_state} =
             App.handle_info(
               {:room_session_snapshot, "room-1",
                %{
                  "room_id" => "room-1",
                  "status" => "running",
                  "dispatch_state" => %{"completed_slots" => 3, "total_slots" => 6},
                  "participants" => [],
                  "timeline" => [%{"kind" => "contribution.recorded", "cursor" => "evt-32"}],
                  "context_objects" => [
                    %{
                      "context_id" => "ctx-1",
                      "object_type" => "message",
                      "title" => "alice said",
                      "body" => "test message for context"
                    }
                  ]
                }},
               state
             )

    assert next_state.snapshot["dispatch_state"] == %{"completed_slots" => 3, "total_slots" => 6}

    assert next_state.snapshot["context_objects"] == [
             %{
               "context_id" => "ctx-1",
               "object_type" => "message",
               "title" => "alice said",
               "body" => "test message for context"
             }
           ]

    assert next_state.event_log_lines == ["contribution.recorded"]
  end

  test "room-session placeholder snapshots do not overwrite authoritative room state", %{
    model: model
  } do
    state =
      %{
        model
        | snapshot: %{
            "room_id" => "room-1",
            "status" => "running",
            "dispatch_state" => %{"completed_slots" => 3, "total_slots" => 6},
            "participants" => [%{"participant_id" => "worker-1"}],
            "timeline" => [%{"kind" => "assignment.opened", "cursor" => "evt-32"}],
            "context_objects" => [
              %{
                "context_id" => "ctx-1",
                "object_type" => "message",
                "title" => "alice said",
                "body" => "authoritative message"
              }
            ],
            "last_sync_at" => "2026-04-09T22:00:00Z"
          }
      }

    assert {:noreply, next_state} =
             App.handle_info(
               {:room_session_snapshot, "room-1",
                %{
                  "room_id" => "room-1",
                  "status" => "idle",
                  "dispatch_state" => %{"completed_slots" => 0, "total_slots" => 0},
                  "participants" => [],
                  "timeline" => [],
                  "context_objects" => [],
                  "last_sync_at" => nil,
                  "last_error" => nil
                }},
               state
             )

    assert next_state.snapshot["status"] == "running"
    assert next_state.snapshot["dispatch_state"] == %{"completed_slots" => 3, "total_slots" => 6}

    assert next_state.snapshot["timeline"] == [
             %{"kind" => "assignment.opened", "cursor" => "evt-32"}
           ]

    assert next_state.snapshot["context_objects"] == [
             %{
               "context_id" => "ctx-1",
               "object_type" => "message",
               "title" => "alice said",
               "body" => "authoritative message"
             }
           ]
  end

  test "room enter restores the draft when the async submit worker exits before server confirmation",
       %{model: model} do
    state =
      %{
        model
        | operator_module: EmptyRoomOperatorStub,
          embedded: self(),
          embedded_module: ExitEmbeddedStub,
          input_buffer: "retry me"
      }

    assert {:noreply, pending_state} = App.handle_event(%Key{code: "enter", kind: "press"}, state)

    assert %{operation_id: operation_id} = pending_state.pending_room_submit

    assert_receive {:room_submit_accepted, "room-1", "retry me", ^operation_id,
                    {:error, {:exit, :submit_timeout}}}

    assert {:noreply, next_state} =
             App.handle_info(
               {:room_submit_accepted, "room-1", "retry me", operation_id,
                {:error, {:exit, :submit_timeout}}},
               pending_state
             )

    assert next_state.pending_room_submit == nil
    assert next_state.input_buffer == "retry me"
    assert next_state.status_severity == :error
    assert next_state.status_line =~ "Submit failed"
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
            "capability_id" => "workspace.exec.session"
          }
        ]
      })

    {next_state, []} = App.update(:wizard_enter, model)

    assert next_state.wizard_step == 4
    assert next_state.status_line == "Press Enter to create and start the room"
    assert next_state.status_severity == :info
  end

  test "wizard create room runs asynchronously and keeps the app responsive" do
    model =
      Model.new(
        operator_module: WizardOperatorStub,
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
            "capability_id" => "workspace.exec.session"
          }
        ]
      })

    assert {:noreply, pending_state} =
             App.handle_event(%Key{code: "enter", kind: "press"}, model)

    assert pending_state.active_screen == :wizard
    assert pending_state.pending_room_create
    assert pending_state.status_line =~ "Creating room"

    assert_receive {:operator_create_room, payload}
    assert payload["dispatch_policy_id"] == "round_robin/v2"

    assert_receive {:add_room, room_id, "http://127.0.0.1:4000/api"}
    assert room_id == pending_state.pending_room_create.room_id

    assert_receive {:wizard_create_result, ^room_id, {:ok, _response}}

    {:noreply, next_state} =
      App.handle_info(
        {:wizard_create_result, room_id, {:ok, %{"room_id" => room_id}}},
        pending_state
      )

    assert next_state.active_screen == :room
    assert next_state.pending_room_create == nil
    assert next_state.status_line =~ "run started in background"
    assert room_id == next_state.room_id

    assert_receive {:operator_start_room_run_operation, ^room_id, opts}

    assert Keyword.get(opts, :assignment_timeout_ms) == 180_000
    client_operation_id = Keyword.fetch!(opts, :client_operation_id)
    assert Keyword.get(opts, :operation_id) == client_operation_id

    assert_receive {:room_run_operation_started, ^room_id, ^client_operation_id,
                    {:ok,
                     %{
                       "operation_id" => "server-room-run-op-1",
                       "client_operation_id" => ^client_operation_id,
                       "status" => "accepted"
                     }}}

    {:noreply, run_started_state} =
      App.handle_info(
        {:room_run_operation_started, room_id, client_operation_id,
         {:ok,
          %{
            "operation_id" => "server-room-run-op-1",
            "client_operation_id" => client_operation_id,
            "status" => "accepted"
          }}},
        next_state
      )

    assert run_started_state.pending_room_run == %{
             room_id: room_id,
             operation_id: "server-room-run-op-1",
             client_operation_id: client_operation_id
           }

    assert run_started_state.status_line =~ "server_op=server-room-run-op-1"
    assert run_started_state.status_line =~ "client_op=#{client_operation_id}"
  end

  test "run room timeout is downgraded when room activity is already visible", %{model: model} do
    state =
      %{
        model
        | operator_module: RunTimeoutOperatorStub,
          room_id: "room-1",
          event_log_lines: ["assignment.started  running  phase=analysis"]
      }

    assert {:noreply, next_state} =
             App.handle_info(
               {:run_room_result, "room-1", "room_run-abc123",
                {:error,
                 {:timeout,
                  %{
                    method: "POST",
                    path: "/rooms/room-1/run",
                    request_timeout_ms: 210_000,
                    elapsed_ms: 210_005,
                    operation_id: "room_run-abc123"
                  }}}},
               state
             )

    assert next_state.status_severity == :warn
    assert next_state.status_line =~ "server activity is visible"
    assert next_state.status_line =~ "room_run-abc123"
  end

  test "wizard escape warns instead of trapping the terminal while creation is pending" do
    state =
      Model.new([])
      |> Map.put(:active_screen, :wizard)
      |> Map.put(:wizard_step, 4)
      |> Map.put(:pending_room_create, %{room_id: "room-123"})

    {next_state, []} = App.update(:wizard_escape, state)

    assert next_state.wizard_step == 4
    assert next_state.status_line =~ "Room creation is in progress"
    assert next_state.status_severity == :warn
  end

  test "refresh_auth_state loads server-backed publish auth for the current participant" do
    state =
      Model.new(
        operator_module: PublishOperatorStub,
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
        operator_module: PublishOperatorStub,
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
