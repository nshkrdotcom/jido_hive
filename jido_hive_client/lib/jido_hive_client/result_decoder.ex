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

  defp normalize(%{"actions" => actions} = decoded) when is_list(actions) do
    {:ok,
     %{
       "summary" => normalize_summary(Map.get(decoded, "summary"), actions),
       "actions" => Enum.map(actions, &normalize_action/1),
       "artifacts" => normalize_artifacts(Map.get(decoded, "artifacts", []))
     }}
  end

  defp normalize(%{"ops" => ops} = decoded) when is_list(ops) do
    {:ok,
     %{
       "summary" => normalize_summary(Map.get(decoded, "summary"), ops),
       "actions" => Enum.map(ops, &normalize_action/1),
       "artifacts" => normalize_artifacts(Map.get(decoded, "artifacts", []))
     }}
  end

  defp normalize(_decoded), do: {:error, :invalid_contract}

  defp normalize_action(action) when is_map(action) do
    op = normalize_operation(Map.get(action, "op") || Map.get(action, "kind"))

    %{
      "op" => op,
      "title" =>
        Map.get(action, "title") || Map.get(action, "ref") || Map.get(action, "id") || op,
      "body" =>
        Map.get(action, "body") || Map.get(action, "content") || Map.get(action, "text") || "",
      "severity" => Map.get(action, "severity"),
      "targets" => normalize_targets(action_targets(action))
    }
  end

  defp action_targets(action) do
    case Map.get(action, "targets") do
      targets when is_list(targets) ->
        targets

      _other ->
        maybe_inline_target(action)
    end
  end

  defp maybe_inline_target(action) do
    case {Map.get(action, "entry_ref"), Map.get(action, "dispute_id")} do
      {nil, nil} -> []
      {entry_ref, dispute_id} -> [%{"entry_ref" => entry_ref, "dispute_id" => dispute_id}]
    end
  end

  defp normalize_targets(targets) when is_list(targets),
    do: Enum.map(targets, &normalize_target/1)

  defp normalize_targets(_other), do: []

  defp normalize_target(target) when is_map(target) do
    %{
      "entry_ref" => Map.get(target, "entry_ref"),
      "dispute_id" => Map.get(target, "dispute_id")
    }
  end

  defp normalize_target(_other), do: %{"entry_ref" => nil, "dispute_id" => nil}

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

  defp normalize_summary(summary, _actions) when is_binary(summary) and summary != "", do: summary

  defp normalize_summary(_summary, actions) do
    ops =
      actions
      |> Enum.map(&(Map.get(&1, "op") || Map.get(&1, "kind")))
      |> Enum.map(&normalize_operation/1)
      |> Enum.reject(&blank_value?/1)

    case ops do
      [] -> "collaboration response"
      _other -> "collaboration response with actions: #{Enum.join(ops, ", ")}"
    end
  end

  defp normalize_operation(value) when is_binary(value), do: String.upcase(value)
  defp normalize_operation(_value), do: nil

  defp blank_value?(value), do: is_nil(value) or value == ""

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
