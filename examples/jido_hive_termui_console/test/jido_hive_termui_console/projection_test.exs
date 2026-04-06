defmodule JidoHiveTermuiConsole.ProjectionTest do
  use ExUnit.Case, async: true

  alias JidoHiveTermuiConsole.Projection

  defp snapshot do
    %{
      timeline: [
        %{"body" => "Investigating auth timeout", "metadata" => %{"participant_id" => "alice"}},
        %{"body" => "Redis is healthy", "metadata" => %{"participant_id" => "bob"}}
      ],
      context_objects: [
        %{"context_id" => "ctx-1", "object_type" => "hypothesis", "title" => "Redis timeout"},
        %{
          "context_id" => "ctx-2",
          "object_type" => "contradiction",
          "title" => "Datadog says Redis is fine"
        },
        %{
          "context_id" => "ctx-3",
          "object_type" => "decision",
          "title" => "Rollback registry deploy"
        }
      ]
    }
  end

  test "formats conversation lines with participant attribution" do
    assert Projection.conversation_lines(snapshot()) == [
             "alice: Investigating auth timeout",
             "bob: Redis is healthy"
           ]
  end

  test "orders context objects and groups them into sectioned lines" do
    assert Projection.display_context_objects(snapshot()) |> Enum.map(& &1["context_id"]) == [
             "ctx-3",
             "ctx-2",
             "ctx-1"
           ]

    assert Projection.context_lines(snapshot(), 1) == [
             "DECISION",
             "  Rollback registry deploy",
             "CONTRADICTION",
             "> Datadog says Redis is fine",
             "HYPOTHESIS",
             "  Redis timeout"
           ]
  end
end
