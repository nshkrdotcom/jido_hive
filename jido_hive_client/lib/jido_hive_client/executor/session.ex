defmodule JidoHiveClient.Executor.Session do
  @moduledoc false

  @behaviour JidoHiveClient.Executor

  alias Jido.Harness
  alias Jido.Harness.ExecutionEvent
  alias JidoHiveClient.{CollaborationPrompt, ResultDecoder, Status}

  @runtime_id :asm

  @impl true
  def run(job, opts) when is_map(job) and is_list(opts) do
    provider = Keyword.get(opts, :provider, provider(job))
    model = Keyword.get(opts, :model) || default_model(provider)
    reasoning_effort = Keyword.get(opts, :reasoning_effort, :low)

    request =
      CollaborationPrompt.to_run_request(
        job,
        run_request_opts(job, Keyword.put(opts, :model, model))
      )

    session_id = Keyword.get(opts, :session_id, default_session_id(job))
    run_id = Keyword.get(opts, :run_id, default_run_id(job))

    start_opts =
      opts
      |> Keyword.drop([:run_id, :allowed_tools, :timeout_ms, :model])
      |> Keyword.put_new(:provider, provider)
      |> Keyword.put_new(:session_id, session_id)
      |> Keyword.put_new(:cwd, workspace_root(job, opts))

    Status.execution_started(
      job,
      Keyword.merge(opts, provider: provider, model: model, reasoning_effort: reasoning_effort)
    )

    with {:ok, session} <- Harness.start_session(@runtime_id, start_opts),
         {:ok, run, stream} <-
           Harness.stream_run(session, request,
             run_id: run_id,
             driver: Keyword.get(opts, :driver),
             driver_opts: driver_opts(job, Keyword.put(opts, :reasoning_effort, reasoning_effort))
           ) do
      result =
        stream
        |> Enum.to_list()
        |> build_response(job, session, run, opts)

      Status.execution_finished(job, result)
      :ok = Harness.stop_session(session)
      {:ok, result}
    else
      {:error, _} = error ->
        Status.execution_failed(job, error)
        error
    end
  end

  defp build_response(events, job, session, run, opts) do
    projection = project(events, run, session)

    case ResultDecoder.decode(projection.execution["text"]) do
      {:ok, decoded_payload} ->
        finalize_response(job, decoded_payload, projection, events)

      {:error, reason} ->
        build_repaired_or_invalid_response(events, job, session, run, opts, projection, reason)
    end
  end

  defp finalize_response(job, decoded_payload, projection, events) do
    %{
      "job_id" => Map.get(job, "job_id"),
      "status" => projection.execution["status"],
      "summary" => decoded_payload["summary"],
      "actions" => decoded_payload["actions"],
      "artifacts" => decoded_payload["artifacts"],
      "events" => Enum.map(events, &normalize_event/1),
      "tool_events" => projection.tool_events,
      "approvals" => projection.approvals,
      "execution" => projection.execution
    }
  end

  defp build_repaired_or_invalid_response(events, job, session, run, opts, projection, reason) do
    case repair_response(session, job, run, opts, projection.execution["text"]) do
      {:ok, repair_events, repair_projection, decoded_payload} ->
        finalize_response(
          job,
          decoded_payload,
          merge_repair_projection(projection, repair_projection, reason),
          events ++ repair_events
        )

      :error ->
        finalize_response(
          job,
          invalid_json_response(reason),
          projection
          |> put_in([:execution, "status"], "failed")
          |> put_in([:execution, "error"], %{"reason" => inspect(reason)}),
          events
        )
    end
  end

  defp project(events, run, session) do
    Enum.reduce(events, initial_projection(run, session), fn event, projection ->
      projection
      |> append_text(event)
      |> collect_cost(event)
      |> collect_tool_event(event)
      |> collect_approval(event)
      |> collect_status(event)
    end)
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

  defp normalize_event(%ExecutionEvent{} = event) do
    %{
      "event_id" => event.event_id,
      "type" => Atom.to_string(event.type),
      "session_id" => event.session_id,
      "run_id" => event.run_id,
      "runtime_id" => Atom.to_string(event.runtime_id),
      "provider" => event.provider && Atom.to_string(event.provider),
      "sequence" => event.sequence,
      "timestamp" => event.timestamp,
      "status" => event.status && Atom.to_string(event.status),
      "payload" => event.payload,
      "metadata" => event.metadata
    }
  end

  defp provider(job) do
    case get_in(job, ["session", "provider"]) || Map.get(job, "provider") do
      value when is_binary(value) -> String.to_atom(value)
      value when is_atom(value) -> value
      _other -> :codex
    end
  end

  defp workspace_root(job, opts) do
    Keyword.get(opts, :cwd) ||
      get_in(job, ["session", "workspace_root"]) ||
      Map.get(job, "workspace_root") ||
      File.cwd!()
  end

  defp default_session_id(job) do
    "session-#{job["room_id"]}-#{job["participant_id"]}"
  end

  defp default_run_id(job) do
    "run-#{job["job_id"]}"
  end

  defp invalid_json_response(reason) do
    %{
      "summary" => "execution produced invalid collaboration JSON",
      "actions" => [],
      "artifacts" => [
        %{
          "artifact_type" => "note",
          "title" => "invalid_json",
          "body" => inspect(reason)
        }
      ]
    }
  end

  defp run_request_opts(job, opts) do
    [
      cwd: workspace_root(job, opts),
      model: Keyword.get(opts, :model),
      timeout_ms: Keyword.get(opts, :timeout_ms),
      allowed_tools: Keyword.get(opts, :allowed_tools)
    ]
  end

  defp driver_opts(job, opts) do
    opts
    |> Keyword.get(:driver_opts, [])
    |> Keyword.put_new(:scenario, scenario_from_job(job))
    |> Keyword.put_new(:reasoning_effort, Keyword.get(opts, :reasoning_effort, :low))
  end

  defp scenario_from_job(job) do
    case get_in(job, ["collaboration_envelope", "turn", "phase"]) do
      "resolution" -> :resolver
      "critique" -> :skeptic
      _other -> :architect
    end
  end

  defp default_model(:codex), do: "gpt-5.4"
  defp default_model(_provider), do: nil

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

  defp repair_response(_session, _job, _run, _opts, ""), do: :error

  defp repair_response(session, job, run, opts, text) do
    Status.repair_started(job, :invalid_collaboration_json)

    request =
      CollaborationPrompt.to_repair_run_request(text, job,
        cwd: workspace_root(job, opts),
        model: Keyword.get(opts, :model),
        timeout_ms: min(Keyword.get(opts, :timeout_ms, 30_000), 30_000)
      )

    with {:ok, repair_run, repair_stream} <-
           Harness.stream_run(session, request,
             run_id: "#{run.run_id}-repair",
             driver: Keyword.get(opts, :driver),
             driver_opts: driver_opts(job, opts)
           ),
         repair_events <- Enum.to_list(repair_stream),
         repair_projection <- project(repair_events, repair_run, session),
         {:ok, decoded_payload} <- ResultDecoder.decode(repair_projection.execution["text"]) do
      {:ok, repair_events, repair_projection, decoded_payload}
    else
      _other -> :error
    end
  end

  defp merge_repair_projection(projection, repair_projection, reason) do
    %{
      execution: %{
        repair_projection.execution
        | "cost" =>
            merge_costs(projection.execution["cost"], repair_projection.execution["cost"]),
          "metadata" =>
            Map.merge(projection.execution["metadata"], %{
              "repair_attempted" => true,
              "repair_reason" => inspect(reason)
            })
      },
      tool_events: projection.tool_events ++ repair_projection.tool_events,
      approvals: projection.approvals ++ repair_projection.approvals
    }
  end

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
  defp known_atom_key("repair"), do: :repair
  defp known_atom_key("status"), do: :status
  defp known_atom_key("stop_reason"), do: :stop_reason
  defp known_atom_key("text"), do: :text
  defp known_atom_key("type"), do: :type
  defp known_atom_key("usage"), do: :usage
  defp known_atom_key(_key), do: nil
end
