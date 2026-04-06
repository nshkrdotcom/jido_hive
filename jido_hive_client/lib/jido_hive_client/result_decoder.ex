defmodule JidoHiveClient.ResultDecoder do
  @moduledoc false

  @spec decode(String.t() | nil) :: {:ok, map()} | {:error, term()}
  def decode(nil), do: {:error, :missing_text}

  def decode(text) when is_binary(text) do
    with {:ok, json} <- extract_json(text),
         {:ok, decoded} <- Jason.decode(json) do
      normalize(decoded)
    end
  end

  defp normalize(%{} = decoded) do
    contribution_type = Map.get(decoded, "contribution_type")

    if is_binary(contribution_type) and String.trim(contribution_type) != "" do
      {:ok,
       %{
         "summary" => normalize_summary(Map.get(decoded, "summary"), contribution_type),
         "contribution_type" => contribution_type,
         "authority_level" => Map.get(decoded, "authority_level") || "advisory",
         "context_objects" => normalize_context_objects(Map.get(decoded, "context_objects", [])),
         "artifacts" => normalize_artifacts(Map.get(decoded, "artifacts", []))
       }}
    else
      {:error, :invalid_contract}
    end
  end

  defp normalize_summary(summary, _contribution_type) when is_binary(summary) and summary != "",
    do: summary

  defp normalize_summary(_summary, contribution_type), do: "#{contribution_type} contribution"

  defp normalize_context_objects(context_objects) when is_list(context_objects) do
    Enum.map(context_objects, &normalize_context_object/1)
  end

  defp normalize_context_objects(_other), do: []

  defp normalize_context_object(context_object) when is_map(context_object) do
    %{
      "object_type" => Map.get(context_object, "object_type"),
      "title" => Map.get(context_object, "title"),
      "body" => Map.get(context_object, "body"),
      "data" => normalize_map(Map.get(context_object, "data", %{})),
      "scope" => normalize_scope(Map.get(context_object, "scope", %{})),
      "uncertainty" => normalize_uncertainty(Map.get(context_object, "uncertainty", %{})),
      "relations" => normalize_relations(Map.get(context_object, "relations", []))
    }
  end

  defp normalize_context_object(_other) do
    %{
      "object_type" => nil,
      "title" => nil,
      "body" => nil,
      "data" => %{},
      "scope" => %{"read" => ["room"], "write" => ["author"]},
      "uncertainty" => %{"status" => "provisional", "confidence" => nil},
      "relations" => []
    }
  end

  defp normalize_scope(scope) when is_map(scope) do
    %{
      "read" => list_of_strings(Map.get(scope, "read", ["room"])),
      "write" => list_of_strings(Map.get(scope, "write", ["author"]))
    }
  end

  defp normalize_scope(_other), do: %{"read" => ["room"], "write" => ["author"]}

  defp normalize_uncertainty(uncertainty) when is_map(uncertainty) do
    %{
      "status" => Map.get(uncertainty, "status", "provisional"),
      "confidence" => Map.get(uncertainty, "confidence"),
      "rationale" => Map.get(uncertainty, "rationale")
    }
  end

  defp normalize_uncertainty(_other), do: %{"status" => "provisional", "confidence" => nil}

  defp normalize_relations(relations) when is_list(relations) do
    Enum.map(relations, fn relation ->
      %{
        "relation" => Map.get(relation, "relation"),
        "target_id" => Map.get(relation, "target_id")
      }
    end)
  end

  defp normalize_relations(_other), do: []

  defp normalize_artifacts(artifacts) when is_list(artifacts) do
    Enum.map(artifacts, fn artifact ->
      %{
        "artifact_type" => Map.get(artifact, "artifact_type"),
        "title" => Map.get(artifact, "title"),
        "body" => Map.get(artifact, "body")
      }
    end)
  end

  defp normalize_artifacts(_other), do: []

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_other), do: %{}

  defp list_of_strings(list) when is_list(list), do: Enum.filter(list, &is_binary/1)
  defp list_of_strings(_other), do: []

  defp extract_json(text) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        {:error, :missing_text}

      valid_json?(trimmed) ->
        {:ok, trimmed}

      fenced = fenced_json(trimmed) ->
        {:ok, fenced}

      extracted = first_object_json(trimmed) ->
        {:ok, extracted}

      true ->
        {:error, :json_not_found}
    end
  end

  defp fenced_json(text) do
    case Regex.run(~r/```json\s*(\{.*\})\s*```/s, text, capture: :all_but_first) do
      [json] when is_binary(json) ->
        if valid_json?(json), do: json

      _ ->
        nil
    end
  end

  defp first_object_json(text) do
    chars = String.to_charlist(text)

    chars
    |> Enum.with_index()
    |> Enum.find_value(fn
      {?{, index} -> balanced_json(chars, index)
      _other -> nil
    end)
  end

  defp balanced_json(chars, start_index) do
    {json_chars, depth, _in_string, _escaped, _started?} =
      Enum.reduce_while(
        Enum.drop(chars, start_index),
        {[], 0, false, false, false},
        &scan_json_char/2
      )

    json =
      json_chars
      |> Enum.reverse()
      |> to_string()
      |> String.trim()

    if depth == 0 and valid_json?(json), do: json
  end

  defp valid_json?(value) when is_binary(value) do
    match?({:ok, _}, Jason.decode(value))
  end

  defp scan_json_char(char, {acc, depth, in_string, true, _started?}) do
    {:cont, {[char | acc], depth, in_string, false, true}}
  end

  defp scan_json_char(?\\ = char, {acc, depth, true, false, _started?}) do
    {:cont, {[char | acc], depth, true, true, true}}
  end

  defp scan_json_char(?" = char, {acc, depth, in_string, false, _started?}) do
    {:cont, {[char | acc], depth, not in_string, false, true}}
  end

  defp scan_json_char(char, {acc, depth, true, false, _started?}) do
    {:cont, {[char | acc], depth, true, false, true}}
  end

  defp scan_json_char(?{ = char, {acc, depth, false, false, _started?}) do
    {:cont, {[char | acc], depth + 1, false, false, true}}
  end

  defp scan_json_char(?} = char, {acc, depth, false, false, _started?}) do
    updated = {[char | acc], depth - 1, false, false, true}

    if elem(updated, 1) == 0 do
      {:halt, updated}
    else
      {:cont, updated}
    end
  end

  defp scan_json_char(char, {acc, depth, false, false, true}) do
    {:cont, {[char | acc], depth, false, false, true}}
  end

  defp scan_json_char(_char, state), do: {:cont, state}
end
