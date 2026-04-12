defmodule JidoHiveWorkerRuntime.ResultDecoder do
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
    kind = normalize_text(value(decoded, "kind"))
    payload = map_value(decoded, "payload")
    meta = map_value(decoded, "meta")

    if valid_text?(kind) do
      {:ok,
       %{
         "kind" => kind,
         "payload" => normalize_payload(payload, kind),
         "meta" => normalize_meta(meta)
       }}
    else
      {:error, :invalid_contract}
    end
  end

  defp normalize_payload(payload, kind) when is_map(payload) do
    %{}
    |> Map.put("summary", normalize_summary(value(payload, "summary"), kind))
    |> Map.put("context_objects", normalize_context_objects(value(payload, "context_objects")))
    |> Map.put("artifacts", normalize_artifacts(value(payload, "artifacts")))
    |> maybe_put("text", normalize_text(value(payload, "text")))
    |> maybe_put("title", normalize_text(value(payload, "title")))
    |> maybe_put("extension", map_value(payload, "extension"))
  end

  defp normalize_meta(meta) when is_map(meta) do
    %{}
    |> maybe_put("authority_level", normalize_text(value(meta, "authority_level")))
    |> maybe_put("status", normalize_text(value(meta, "status")))
  end

  defp normalize_summary(summary, _kind) when is_binary(summary) and summary != "", do: summary
  defp normalize_summary(_summary, kind), do: "#{kind} contribution"

  defp normalize_context_objects(context_objects) when is_list(context_objects) do
    context_objects
    |> Enum.map(&normalize_context_object/1)
    |> Enum.reject(&empty_context_object?/1)
  end

  defp normalize_context_objects(_other), do: []

  defp normalize_context_object(context_object) when is_map(context_object) do
    %{
      "object_type" => normalize_text(value(context_object, "object_type")),
      "title" => normalize_text(value(context_object, "title")),
      "body" => normalize_text(value(context_object, "body")),
      "data" => map_value(context_object, "data"),
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
    relations
    |> Enum.map(fn relation ->
      %{
        "relation" => normalize_text(value(relation, "relation")),
        "target_id" => normalize_text(value(relation, "target_id"))
      }
    end)
    |> Enum.reject(&(is_nil(Map.get(&1, "relation")) or is_nil(Map.get(&1, "target_id"))))
  end

  defp normalize_relations(_other), do: []

  defp normalize_artifacts(artifacts) when is_list(artifacts) do
    artifacts
    |> Enum.map(fn artifact ->
      %{
        "artifact_type" => normalize_text(value(artifact, "artifact_type")),
        "title" => normalize_text(value(artifact, "title")),
        "body" => normalize_text(value(artifact, "body"))
      }
    end)
    |> Enum.reject(
      &(is_nil(Map.get(&1, "artifact_type")) and is_nil(Map.get(&1, "title")) and
          is_nil(Map.get(&1, "body")))
    )
  end

  defp normalize_artifacts(_other), do: []

  defp list_of_strings(list) when is_list(list), do: Enum.filter(list, &is_binary/1)
  defp list_of_strings(_other), do: []

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, %{} = value) when map_size(value) == 0, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    case value(map, key) do
      %{} = value -> value
      _other -> %{}
    end
  end

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_text(_other), do: nil

  defp valid_text?(value) when is_binary(value), do: value != ""
  defp valid_text?(_value), do: false

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
