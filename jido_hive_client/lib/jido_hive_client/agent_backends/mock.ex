defmodule JidoHiveClient.AgentBackends.Mock do
  @moduledoc false

  @behaviour JidoHiveClient.AgentBackend

  alias JidoHiveClient.{ChatInput, InterceptedContribution}

  @impl true
  def extract_contribution(%ChatInput{} = chat_input, _opts) do
    text = String.trim(chat_input.text)

    context_objects =
      chat_input
      |> generated_context_objects(text)
      |> anchor_context_objects(chat_input)

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

  defp generated_context_objects(%ChatInput{} = chat_input, text) do
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
  end

  defp anchor_context_objects(context_objects, %ChatInput{} = chat_input) do
    case {selected_context_id(chat_input), selected_relation_mode(chat_input)} do
      {nil, _mode} ->
        Enum.map(context_objects, &drop_nil_relations/1)

      {_target_id, "none"} ->
        Enum.map(context_objects, &drop_nil_relations/1)

      {target_id, _mode} ->
        {message_objects, semantic_objects} =
          Enum.split_with(context_objects, &(&1["object_type"] == "message"))

        anchored_semantic_objects =
          semantic_objects
          |> Enum.map(&anchor_object(&1, chat_input, target_id))
          |> Enum.map(&drop_nil_relations/1)

        if anchored_semantic_objects == [] do
          message_objects ++ [anchored_note(chat_input, target_id)]
        else
          message_objects ++ anchored_semantic_objects
        end
    end
  end

  defp anchor_object(object, %ChatInput{} = chat_input, target_id) do
    relation =
      explicit_relation(chat_input) ||
        contextual_relation(object["object_type"])

    case relation do
      nil ->
        object

      relation_name ->
        Map.put(object, "relations", [%{"relation" => relation_name, "target_id" => target_id}])
    end
  end

  defp anchored_note(%ChatInput{} = chat_input, target_id) do
    %{
      "object_type" => "note",
      "title" => title_from(chat_input.text, "Anchored note"),
      "body" => chat_input.text,
      "relations" => [
        %{
          "relation" => explicit_relation(chat_input) || "references",
          "target_id" => target_id
        }
      ]
    }
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
        "body" => text
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

  defp selected_context_id(%ChatInput{} = chat_input) do
    case chat_input.local_context["selected_context_id"] do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          normalized -> normalized
        end

      _other ->
        nil
    end
  end

  defp explicit_relation(%ChatInput{} = chat_input) do
    case selected_relation_mode(chat_input) do
      "contextual" -> nil
      "none" -> nil
      relation -> relation
    end
  end

  defp selected_relation_mode(%ChatInput{} = chat_input) do
    case chat_input.local_context["selected_relation"] do
      value when is_binary(value) and value != "" -> value
      _other -> "contextual"
    end
  end

  defp contextual_relation("hypothesis"), do: "derives_from"
  defp contextual_relation("evidence"), do: "supports"
  defp contextual_relation("contradiction"), do: "contradicts"
  defp contextual_relation("decision_candidate"), do: "derives_from"
  defp contextual_relation("question"), do: "references"
  defp contextual_relation("note"), do: "references"
  defp contextual_relation(_object_type), do: nil

  defp drop_nil_relations(object) do
    relations =
      object
      |> Map.get("relations", [])
      |> Enum.filter(fn relation ->
        is_binary(relation["relation"]) and is_binary(relation["target_id"]) and
          String.trim(relation["target_id"]) != ""
      end)

    case relations do
      [] -> Map.delete(object, "relations")
      _ -> Map.put(object, "relations", relations)
    end
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
