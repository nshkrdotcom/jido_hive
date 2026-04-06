defmodule JidoHiveClient.AgentBackends.Mock do
  @moduledoc false

  @behaviour JidoHiveClient.AgentBackend

  alias JidoHiveClient.{ChatInput, InterceptedContribution}

  @impl true
  def extract_contribution(%ChatInput{} = chat_input, _opts) do
    text = String.trim(chat_input.text)

    context_objects =
      [message_object(chat_input)] ++
        Enum.reject(
          [
            question_object(text),
            hypothesis_object(text),
            evidence_object(text),
            contradiction_object(text),
            decision_candidate_object(text)
          ],
          &is_nil/1
        )

    {:ok,
     InterceptedContribution.new!(%{
       chat_text: chat_input.text,
       summary: chat_input.text,
       contribution_type: "chat",
       authority_level: "advisory",
       context_objects: context_objects,
       tags: Enum.map(context_objects, &Map.fetch!(&1, "object_type")),
       raw_backend_output: %{"backend" => "mock", "rule_count" => length(context_objects) - 1}
     })}
  end

  defp question_object(text) do
    if String.contains?(text, "?") do
      %{
        "object_type" => "question",
        "title" => "Open question",
        "body" => text
      }
    end
  end

  defp hypothesis_object(text) do
    if Regex.match?(~r/\b(i think|maybe|likely)\b/i, text) do
      %{
        "object_type" => "hypothesis",
        "title" => title_from(text, "Hypothesis"),
        "body" => text,
        "uncertainty" => %{"status" => "provisional", "confidence" => 0.6}
      }
    end
  end

  defp evidence_object(text) do
    if Regex.match?(~r/\bbecause\b/i, text) do
      %{
        "object_type" => "evidence",
        "title" => "Supporting evidence",
        "body" => text,
        "relations" => [%{"relation" => "supports", "target_id" => nil}]
      }
    end
  end

  defp contradiction_object(text) do
    if Regex.match?(~r/\b(no|actually|broken)\b/i, text) do
      %{
        "object_type" => "contradiction",
        "title" => "Contradiction detected",
        "body" => text
      }
    end
  end

  defp decision_candidate_object(text) do
    if Regex.match?(~r/\b(we should|let's)\b/i, text) do
      %{
        "object_type" => "decision_candidate",
        "title" => "Candidate decision",
        "body" => text
      }
    end
  end

  defp message_object(%ChatInput{} = chat_input) do
    %{
      "object_type" => "message",
      "title" => "#{chat_input.participant_id} said",
      "body" => chat_input.text,
      "data" => %{"participant_kind" => chat_input.participant_kind}
    }
  end

  defp title_from(text, fallback) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
      "" -> fallback
      normalized -> String.slice(normalized, 0, 72)
    end
  end
end
