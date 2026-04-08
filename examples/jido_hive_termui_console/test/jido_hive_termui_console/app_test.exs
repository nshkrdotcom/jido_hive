defmodule JidoHiveTermuiConsole.AppTest do
  use ExUnit.Case, async: true

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
    def snapshot(server), do: Agent.get(server, & &1.snapshot)
    def refresh(server), do: {:ok, snapshot(server)}

    def submit_chat(server, attrs) do
      Agent.update(server, &Map.put(&1, :submitted, attrs))
      {:ok, %{"summary" => Map.get(attrs, :text) || Map.get(attrs, "text")}}
    end

    def accept_context(_server, _context_id, _attrs), do: {:ok, %{"authority_level" => "binding"}}
  end

  setup do
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

  test "event log updates append formatted lines", %{model: model} do
    {next_state, []} =
      App.handle_info(
        {:event_log_update, [%{"kind" => "contribution.recorded", "cursor" => "c1"}], "c1"},
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
end
