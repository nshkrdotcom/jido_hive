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
    contribution = contribution_payload(decoded)
    contribution_type = contribution_type(contribution, decoded)

    if is_binary(contribution_type) and String.trim(contribution_type) != "" do
      {:ok,
       %{
         "summary" => normalize_summary(value(contribution, "summary"), contribution_type),
         "contribution_type" => contribution_type,
         "authority_level" => value(contribution, "authority_level") || "advisory",
         "context_objects" =>
           normalize_context_objects(context_object_source(contribution, decoded)),
         "artifacts" => normalize_artifacts(value(contribution, "artifacts"))
       }}
    else
      {:error, :invalid_contract}
    end
  end

  defp contribution_payload(%{} = decoded) do
    case value(decoded, "contribution") do
      %{} = contribution -> contribution
      _other -> decoded
    end
  end

  defp contribution_type(contribution, decoded) do
    value(contribution, "contribution_type") || infer_contribution_type(contribution, decoded)
  end

  defp infer_contribution_type(contribution, decoded) do
    contribution
    |> context_object_source(decoded)
    |> Enum.map(&legacy_object_type/1)
    |> infer_from_object_types()
  end

  defp infer_from_object_types(object_types) do
    cond do
      Enum.any?(object_types, &(&1 == "decision")) -> "decision"
      Enum.any?(object_types, &(&1 == "artifact")) -> "artifact"
      Enum.any?(object_types, &(&1 == "constraint")) -> "constraint"
      object_types != [] -> "reasoning"
      true -> nil
    end
  end

  defp context_object_source(contribution, decoded) do
    cond do
      is_list(value(contribution, "context_objects")) -> value(contribution, "context_objects")
      is_list(value(contribution, "objects")) -> value(contribution, "objects")
      is_list(value(decoded, "contributions")) -> value(decoded, "contributions")
      true -> []
    end
  end

  defp normalize_summary(summary, _contribution_type) when is_binary(summary) and summary != "",
    do: summary

  defp normalize_summary(_summary, contribution_type), do: "#{contribution_type} contribution"

  defp normalize_context_objects(context_objects) when is_list(context_objects) do
    context_objects
    |> Enum.map(&normalize_context_object/1)
    |> Enum.reject(&empty_context_object?/1)
  end

  defp normalize_context_objects(_other), do: []

  defp normalize_context_object(context_object) when is_map(context_object) do
    nested_object =
      case value(context_object, "object") do
        %{} = object -> object
        _other -> %{}
      end

    %{
      "object_type" => legacy_object_type(context_object),
      "title" => legacy_title(context_object, nested_object),
      "body" => legacy_body(context_object, nested_object),
      "data" => legacy_data(context_object, nested_object),
      "scope" => normalize_scope(value(context_object, "scope")),
      "uncertainty" => normalize_uncertainty(value(context_object, "uncertainty")),
      "relations" => normalize_relations(value(context_object, "relations"))
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

  defp empty_context_object?(%{"object_type" => nil, "title" => nil, "body" => nil}), do: true
  defp empty_context_object?(_context_object), do: false

  defp legacy_object_type(context_object) do
    nested_object =
      case value(context_object, "object") do
        %{} = object -> object
        _other -> %{}
      end

    value(context_object, "object_type") ||
      value(context_object, "type") ||
      value(nested_object, "object_type") ||
      value(nested_object, "kind") ||
      value(nested_object, "type")
  end

  defp legacy_title(context_object, nested_object) do
    value(context_object, "title") ||
      value(nested_object, "title") ||
      compact_title(legacy_body(context_object, nested_object))
  end

  defp legacy_body(context_object, nested_object) do
    body_candidate =
      first_present([
        value(context_object, "body"),
        value(context_object, "text"),
        value(context_object, "content"),
        value(nested_object, "body"),
        value(nested_object, "text"),
        value(nested_object, "content")
      ])

    normalize_body(body_candidate)
  end

  defp legacy_data(context_object, nested_object) do
    %{}
    |> merge_map(value(context_object, "data"))
    |> maybe_put("object_id", value(context_object, "object_id") || value(nested_object, "id"))
    |> maybe_put(
      "content",
      map_content(value(context_object, "content"), value(nested_object, "content"))
    )
  end

  defp normalize_scope(scope) when is_map(scope) do
    %{
      "read" => list_of_strings(value(scope, "read") || ["room"]),
      "write" => list_of_strings(value(scope, "write") || ["author"])
    }
  end

  defp normalize_scope(_other), do: %{"read" => ["room"], "write" => ["author"]}

  defp normalize_uncertainty(uncertainty) when is_map(uncertainty) do
    %{
      "status" => value(uncertainty, "status") || "provisional",
      "confidence" => value(uncertainty, "confidence"),
      "rationale" => value(uncertainty, "rationale")
    }
  end

  defp normalize_uncertainty(_other), do: %{"status" => "provisional", "confidence" => nil}

  defp normalize_relations(relations) when is_list(relations) do
    Enum.map(relations, fn relation ->
      %{
        "relation" =>
          value(relation, "relation") || value(relation, "relation_type") ||
            value(relation, "type"),
        "target_id" => value(relation, "target_id") || value(relation, "to")
      }
    end)
  end

  defp normalize_relations(_other), do: []

  defp normalize_artifacts(artifacts) when is_list(artifacts) do
    Enum.map(artifacts, fn artifact ->
      %{
        "artifact_type" =>
          value(artifact, "artifact_type") || value(artifact, "object_type") ||
            value(artifact, "type"),
        "title" =>
          value(artifact, "title") || compact_title(normalize_body(value(artifact, "body"))),
        "body" =>
          normalize_body(
            first_present([
              value(artifact, "body"),
              value(artifact, "text"),
              value(artifact, "content")
            ])
          )
      }
    end)
  end

  defp normalize_artifacts(_other), do: []

  defp list_of_strings(list) when is_list(list), do: Enum.filter(list, &is_binary/1)
  defp list_of_strings(_other), do: []

  defp normalize_body(value) when is_binary(value), do: value

  defp normalize_body(value) when is_map(value) do
    first_present([
      Map.get(value, "body"),
      Map.get(value, "text"),
      Map.get(value, "content"),
      Map.get(value, "decision"),
      Map.get(value, "summary"),
      Map.get(value, "purpose"),
      Map.get(value, "rationale")
    ]) || Jason.encode!(value)
  end

  defp normalize_body(_other), do: nil

  defp compact_title(nil), do: nil

  defp compact_title(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(8)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      title -> title
    end
  end

  defp first_present(values) when is_list(values) do
    Enum.find_value(values, fn
      value when is_binary(value) and value != "" -> value
      value when is_map(value) and value != %{} -> value
      _other -> nil
    end)
  end

  defp merge_map(map, %{} = incoming), do: Map.merge(map, incoming)
  defp merge_map(map, _other), do: map

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp map_content(%{} = content, _fallback), do: content
  defp map_content(_content, %{} = fallback), do: fallback
  defp map_content(_content, _fallback), do: nil

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

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
