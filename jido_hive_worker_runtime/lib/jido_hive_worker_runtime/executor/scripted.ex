defmodule JidoHiveWorkerRuntime.Executor.Scripted do
  @moduledoc false

  @behaviour JidoHiveWorkerRuntime.Executor

  @impl true
  def run(assignment, opts \\ []) when is_map(assignment) and is_list(opts) do
    role =
      opts
      |> Keyword.get(:role)
      |> normalize_role(Map.get(assignment, "participant_role", "analyst"))

    contribution =
      case role do
        :skeptic -> skeptic_contribution(assignment)
        _ -> analyst_contribution(assignment)
      end

    {:ok, contribution}
  end

  defp normalize_role(nil, fallback), do: normalize_role(fallback, fallback)
  defp normalize_role(role, _fallback) when is_atom(role), do: role
  defp normalize_role(role, _fallback) when is_binary(role), do: String.to_atom(role)

  defp analyst_contribution(assignment) do
    %{
      "assignment_id" => assignment["id"],
      "participant_id" => assignment["participant_id"],
      "kind" => "reasoning",
      "payload" => %{
        "summary" => "analysis pass added substrate beliefs and notes",
        "context_objects" => [
          %{
            "object_type" => "belief",
            "title" => "Server-owned room state",
            "body" => "The server should own room state and issue explicit assignments."
          },
          %{
            "object_type" => "note",
            "title" => "Context views",
            "body" =>
              "Assignments should include a filtered context view instead of a full mutable packet."
          }
        ],
        "artifacts" => []
      },
      "meta" => %{
        "participant_role" => assignment["participant_role"] || "analyst",
        "status" => "completed",
        "tool_events" => [
          %{
            "event_type" => "tool_call",
            "tool_name" => "context.read",
            "status" => "ok",
            "input" => %{"scope" => "room"},
            "output" => %{"brief" => get_in(assignment, ["context", "brief"])}
          }
        ]
      }
    }
  end

  defp skeptic_contribution(assignment) do
    %{
      "assignment_id" => assignment["id"],
      "participant_id" => assignment["participant_id"],
      "kind" => "reasoning",
      "payload" => %{
        "summary" => "critique pass added one open question",
        "context_objects" => [
          %{
            "object_type" => "question",
            "title" => "Human approval path",
            "body" =>
              "The system still needs a clear human authority handoff for binding decisions."
          }
        ],
        "artifacts" => []
      },
      "meta" => %{
        "participant_role" => assignment["participant_role"] || "skeptic",
        "status" => "completed",
        "tool_events" => [
          %{
            "event_type" => "tool_call",
            "tool_name" => "critique.scan",
            "status" => "ok",
            "input" => %{"focus" => "gaps"},
            "output" => %{"issue_count" => 1}
          }
        ]
      }
    }
  end
end
