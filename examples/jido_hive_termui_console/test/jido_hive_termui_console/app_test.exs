defmodule JidoHiveTermuiConsole.AppTest do
  use ExUnit.Case, async: true

  alias JidoHiveTermuiConsole.{App, Model}

  defmodule EmbeddedStub do
    def snapshot(server), do: Agent.get(server, & &1.snapshot)

    def submit_chat(server, attrs) do
      Agent.update(server, &Map.put(&1, :submitted, attrs))
      {:ok, %{"summary" => Map.get(attrs, :text) || Map.get(attrs, "text")}}
    end
  end

  setup do
    snapshot = %{
      timeline: [],
      context_objects: [
        %{
          "context_id" => "ctx-1",
          "object_type" => "hypothesis",
          "title" => "Root hypothesis"
        }
      ]
    }

    {:ok, embedded} = Agent.start_link(fn -> %{snapshot: snapshot, submitted: nil} end)

    model =
      Model.new(
        embedded: embedded,
        embedded_module: EmbeddedStub,
        room_id: "room-1",
        participant_id: "alice",
        snapshot: snapshot
      )

    %{embedded: embedded, model: model}
  end

  test "submits plain chat when relation mode is none", %{embedded: embedded, model: model} do
    state = %{model | input_buffer: "plain update", relation_mode: :none}

    {next_state, []} = App.update(:submit_input, state)

    assert next_state.input_buffer == ""

    assert Agent.get(embedded, & &1.submitted) == %{
             text: "plain update"
           }
  end

  test "submits selected relation context when relation mode is explicit", %{
    embedded: embedded,
    model: model
  } do
    state = %{model | input_buffer: "I think auth is broken", relation_mode: :supports}

    {next_state, []} = App.update(:submit_input, state)

    assert next_state.input_buffer == ""

    assert Agent.get(embedded, & &1.submitted) == %{
             text: "I think auth is broken",
             selected_context_id: "ctx-1",
             selected_context_object_type: "hypothesis",
             selected_relation: "supports"
           }
  end
end
