defmodule JidoHiveWorkerRuntime.Executor.Projection do
  @moduledoc false

  alias Jido.Harness.ExecutionEvent

  @spec build([ExecutionEvent.t()], map(), map()) :: map()
  def build(events, run, session) when is_list(events) and is_map(run) and is_map(session) do
    Enum.reduce(events, initial_projection(run, session), fn event, projection ->
      projection
      |> append_text(event)
      |> collect_cost(event)
      |> collect_tool_event(event)
      |> collect_approval(event)
      |> collect_status(event)
    end)
  end

  @spec merge_repair(map(), map(), term()) :: map()
  def merge_repair(projection, repair_projection, reason)
      when is_map(projection) and is_map(repair_projection) do
    %{
      execution: %{
        repair_projection.execution
        | "cost" =>
            merge_costs(
              get_in(projection, [:execution, "cost"]),
              get_in(repair_projection, [:execution, "cost"])
            ),
          "metadata" =>
            Map.merge(get_in(projection, [:execution, "metadata"]) || %{}, %{
              "repair_attempted" => true,
              "repair_reason" => inspect(reason)
            })
      },
      tool_events:
        Map.get(projection, :tool_events, []) ++ Map.get(repair_projection, :tool_events, []),
      approvals: Map.get(projection, :approvals, []) ++ Map.get(repair_projection, :approvals, [])
    }
  end

  defp initial_projection(run, session) do
    %{
      execution: %{
        "run_id" => run.run_id,
        "session_id" => session.session_id,
        "runtime_id" => Atom.to_string(session.runtime_id),
        "provider" => session.provider && Atom.to_string(session.provider),
        "status" => "running",
        "text" => "",
        "cost" => %{},
        "error" => nil,
        "stop_reason" => nil,
        "metadata" => %{}
      },
      tool_events: [],
      approvals: []
    }
  end

  defp append_text(%{execution: execution} = projection, %ExecutionEvent{
         type: :assistant_delta,
         payload: payload
       }) do
    append_execution_text(projection, execution, payload_text(payload))
  end

  defp append_text(%{execution: execution} = projection, %ExecutionEvent{
         type: :assistant_message,
         payload: payload
       }) do
    append_execution_text(
      projection,
      execution,
      assistant_text(payload_value(payload, "content"))
    )
  end

  defp append_text(projection, _event), do: projection

  defp collect_cost(projection, %ExecutionEvent{type: :cost, payload: payload}) do
    update_in(projection, [:execution, "cost"], &Map.merge(&1, normalize_value(payload)))
  end

  defp collect_cost(projection, %ExecutionEvent{type: :result, payload: payload}) do
    case payload |> payload_value("output") |> payload_value("usage") do
      usage when is_map(usage) ->
        update_in(projection, [:execution, "cost"], &Map.merge(&1, normalize_value(usage)))

      _other ->
        projection
    end
  end

  defp collect_cost(projection, _event), do: projection

  defp collect_tool_event(projection, %ExecutionEvent{type: type, payload: payload})
       when type in [:tool_call, :tool_result, :tool_use, :tool_output] do
    %{
      projection
      | tool_events:
          projection.tool_events ++
            [%{"event_type" => Atom.to_string(type), "payload" => normalize_value(payload)}]
    }
  end

  defp collect_tool_event(projection, %ExecutionEvent{type: :raw, payload: payload}) do
    case raw_tool_event(payload) do
      nil ->
        projection

      tool_event ->
        %{projection | tool_events: projection.tool_events ++ [tool_event]}
    end
  end

  defp collect_tool_event(projection, _event), do: projection

  defp collect_approval(projection, %ExecutionEvent{type: type, payload: payload})
       when type in [:approval_requested, :approval_resolved] do
    %{
      projection
      | approvals:
          projection.approvals ++ [%{"event_type" => Atom.to_string(type), "payload" => payload}]
    }
  end

  defp collect_approval(projection, _event), do: projection

  defp collect_status(projection, %ExecutionEvent{type: :result, payload: payload}) do
    projection
    |> put_in([:execution, "status"], "completed")
    |> put_in([:execution, "stop_reason"], payload_value(payload, "stop_reason"))
  end

  defp collect_status(projection, %ExecutionEvent{type: :error, payload: payload}) do
    projection
    |> put_in([:execution, "status"], "failed")
    |> put_in([:execution, "error"], payload)
  end

  defp collect_status(projection, _event), do: projection

  defp append_execution_text(projection, _execution, ""), do: projection

  defp append_execution_text(projection, execution, text) do
    put_in(projection, [:execution, "text"], execution["text"] <> text)
  end

  defp payload_text(payload) do
    payload_value(payload, "content") || payload_value(payload, "text") || ""
  end

  defp assistant_text(content) when is_binary(content), do: content

  defp assistant_text(content) when is_list(content),
    do: Enum.map_join(content, "", &assistant_text/1)

  defp assistant_text(%{} = content), do: assistant_text(payload_text(content))
  defp assistant_text(_content), do: ""

  defp raw_tool_event(payload) do
    content = payload_value(payload, "content")
    item = payload_value(content, "item")

    with type when type in ["item.started", "item.completed"] <- payload_value(content, "type"),
         %{} <- item do
      %{
        "event_type" => raw_tool_event_type(type),
        "payload" => %{
          "tool_name" => raw_tool_name(item),
          "item_id" => payload_value(item, "id"),
          "item_type" => payload_value(item, "type"),
          "status" => payload_value(item, "status"),
          "input" => raw_tool_input(item),
          "output" => raw_tool_output(item)
        }
      }
    else
      _other -> nil
    end
  end

  defp raw_tool_event_type("item.started"), do: "tool_call"
  defp raw_tool_event_type("item.completed"), do: "tool_result"

  defp raw_tool_name(item) do
    case payload_value(item, "type") do
      "command_execution" -> "shell.command"
      type when is_binary(type) -> type
      _other -> "runtime.item"
    end
  end

  defp raw_tool_input(item) do
    %{}
    |> maybe_put("command", payload_value(item, "command"))
  end

  defp raw_tool_output(item) do
    %{}
    |> maybe_put("aggregated_output", payload_value(item, "aggregated_output"))
    |> maybe_put("exit_code", payload_value(item, "exit_code"))
  end

  defp payload_value(nil, _key), do: nil

  defp payload_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, known_atom_key(key))
  end

  defp payload_value(_value, _key), do: nil

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize_value(value)} end)
  end

  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp merge_costs(left, right) do
    Map.merge(left || %{}, right || %{}, fn _key, left_value, right_value ->
      if is_number(left_value) and is_number(right_value) do
        left_value + right_value
      else
        right_value
      end
    end)
  end

  defp known_atom_key("aggregated_output"), do: :aggregated_output
  defp known_atom_key("command"), do: :command
  defp known_atom_key("content"), do: :content
  defp known_atom_key("exit_code"), do: :exit_code
  defp known_atom_key("id"), do: :id
  defp known_atom_key("item"), do: :item
  defp known_atom_key("output"), do: :output
  defp known_atom_key("status"), do: :status
  defp known_atom_key("stop_reason"), do: :stop_reason
  defp known_atom_key("text"), do: :text
  defp known_atom_key("type"), do: :type
  defp known_atom_key("usage"), do: :usage
  defp known_atom_key(_key), do: nil
end
