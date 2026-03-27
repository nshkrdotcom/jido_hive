defmodule JidoHiveClient.Executor.Scripted do
  @moduledoc false

  @behaviour JidoHiveClient.Executor

  @impl true
  def run(job, opts \\ []) when is_map(job) and is_list(opts) do
    role =
      opts
      |> Keyword.get(:role)
      |> normalize_role(Map.get(job, "participant_role", "architect"))

    result =
      case role do
        :skeptic -> skeptic_result(job)
        _ -> architect_result(job)
      end

    {:ok, result}
  end

  defp normalize_role(nil, fallback), do: normalize_role(fallback, fallback)
  defp normalize_role(role, _fallback) when is_atom(role), do: role
  defp normalize_role(role, _fallback) when is_binary(role), do: String.to_atom(role)

  defp architect_result(job) do
    %{
      "job_id" => job["job_id"],
      "participant_id" => job["participant_id"],
      "participant_role" => "architect",
      "summary" => "architect proposed a shared packet of context, instructions, and tool traces",
      "actions" => [
        %{
          "op" => "CLAIM",
          "title" => "Shared packet",
          "body" =>
            "The server should braid context, instructions, and prior tool traces into each turn packet."
        },
        %{
          "op" => "EVIDENCE",
          "title" => "Lineage",
          "body" =>
            "Each client turn should preserve the prior structured actions and tool outcomes as reviewable artifacts."
        },
        %{
          "op" => "PUBLISH",
          "title" => "Publish the reviewed protocol",
          "body" =>
            "Prepare both a GitHub issue draft and a Notion page draft from the shared room state."
        }
      ],
      "tool_events" => [
        %{
          "tool_name" => "context.read",
          "status" => "ok",
          "input" => %{"scope" => "room"},
          "output" => %{"summary" => get_in(job, ["prompt_packet", "context_summary"])}
        },
        %{
          "tool_name" => "instruction.log",
          "status" => "ok",
          "input" => %{
            "count" => length(get_in(job, ["prompt_packet", "shared_instruction_log"]) || [])
          },
          "output" => %{"accepted" => true}
        }
      ]
    }
  end

  defp skeptic_result(job) do
    %{
      "job_id" => job["job_id"],
      "participant_id" => job["participant_id"],
      "participant_role" => "skeptic",
      "summary" => "skeptic opened one high-severity objection against the draft protocol",
      "actions" => [
        %{
          "op" => "OBJECT",
          "title" => "Conflict handling is underspecified",
          "body" =>
            "The packet does not yet explain how contradictory tool outputs remain visible instead of being flattened away.",
          "targets" => [%{"entry_ref" => "claim:1"}],
          "severity" => "high"
        }
      ],
      "tool_events" => [
        %{
          "tool_name" => "critique.scan",
          "status" => "ok",
          "input" => %{"focus" => "contradictions"},
          "output" => %{"issue_count" => 1}
        }
      ]
    }
  end
end
