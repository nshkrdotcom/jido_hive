defmodule JidoHiveWorkerRuntime.Executor.Session do
  @moduledoc false

  @behaviour JidoHiveWorkerRuntime.Executor

  alias Jido.Harness
  alias Jido.Harness.ExecutionEvent

  alias JidoHiveWorkerRuntime.{
    Boundary.ProtocolCodec,
    CollaborationPrompt,
    ExecutionContract,
    ResultDecoder,
    Status
  }

  alias JidoHiveWorkerRuntime.Executor.{Projection, RepairPolicy}

  @runtime_id :asm

  @impl true
  def run(assignment, opts) when is_map(assignment) and is_list(opts) do
    opts = ExecutionContract.apply_session_defaults(assignment, opts)
    provider = Keyword.get(opts, :provider, provider(assignment))
    model = Keyword.get(opts, :model) || default_model(provider)
    reasoning_effort = Keyword.get(opts, :reasoning_effort, :low)

    request =
      CollaborationPrompt.to_run_request(
        assignment,
        run_request_opts(assignment, Keyword.put(opts, :model, model))
      )

    session_id = Keyword.get(opts, :session_id, default_session_id(assignment))
    run_id = Keyword.get(opts, :run_id, default_run_id(assignment))

    start_opts =
      ExecutionContract.start_session_opts(assignment, opts, provider, session_id)

    Status.execution_started(
      assignment,
      Keyword.merge(opts, provider: provider, model: model, reasoning_effort: reasoning_effort),
      request
    )

    with {:ok, session} <- Harness.start_session(@runtime_id, start_opts),
         {:ok, run, stream} <-
           Harness.stream_run(session, request,
             run_id: run_id,
             driver: Keyword.get(opts, :driver),
             driver_opts:
               driver_opts(assignment, Keyword.put(opts, :reasoning_effort, reasoning_effort))
           ) do
      contribution =
        stream
        |> Enum.to_list()
        |> build_response(assignment, session, run, opts)

      Status.execution_finished(assignment, contribution)
      :ok = Harness.stop_session(session)
      {:ok, contribution}
    else
      {:error, _} = error ->
        Status.execution_failed(assignment, error)
        error
    end
  end

  defp build_response(events, assignment, session, run, opts) do
    projection = Projection.build(events, run, session)

    case ResultDecoder.decode(projection.execution["text"]) do
      {:ok, decoded_payload} ->
        finalize_response(assignment, decoded_payload, projection, events)

      {:error, reason} ->
        build_repaired_or_invalid_response(
          events,
          assignment,
          session,
          run,
          opts,
          projection,
          reason
        )
    end
  end

  defp finalize_response(assignment, decoded_payload, projection, events) do
    ProtocolCodec.normalize_contribution(decoded_payload, assignment)
    |> Map.put("status", projection.execution["status"] || "completed")
    |> Map.put("artifacts", decoded_payload["artifacts"] || [])
    |> Map.put("events", Enum.map(events, &normalize_event/1))
    |> Map.put("tool_events", projection.tool_events)
    |> Map.put("approvals", projection.approvals)
    |> Map.put("execution", projection.execution)
  end

  defp build_repaired_or_invalid_response(
         events,
         assignment,
         session,
         run,
         opts,
         projection,
         reason
       ) do
    case repair_response(session, assignment, run, opts, projection.execution["text"]) do
      {:ok, repair_events, repair_projection, decoded_payload} ->
        finalize_response(
          assignment,
          decoded_payload,
          Projection.merge_repair(projection, repair_projection, reason),
          events ++ repair_events
        )

      :error ->
        finalize_response(
          assignment,
          invalid_json_response(reason),
          projection
          |> put_in([:execution, "status"], "failed")
          |> put_in([:execution, "error"], %{"reason" => inspect(reason)}),
          events
        )
    end
  end

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

  defp provider(assignment) do
    case get_in(assignment, ["session", "provider"]) || Map.get(assignment, "provider") do
      "claude" -> :claude
      value when is_binary(value) and value != "" -> :codex
      value when is_atom(value) -> value
      _other -> :codex
    end
  end

  defp workspace_root(assignment, opts) do
    ExecutionContract.workspace_root(assignment, opts)
  end

  defp default_session_id(assignment) do
    "session-#{assignment["room_id"]}-#{assignment["participant_id"]}"
  end

  defp default_run_id(assignment) do
    "run-#{assignment["assignment_id"]}"
  end

  defp invalid_json_response(reason) do
    %{
      "summary" => "execution produced invalid contribution JSON",
      "contribution_type" => "reasoning",
      "authority_level" => "advisory",
      "context_objects" => [],
      "artifacts" => [
        %{
          "artifact_type" => "note",
          "title" => "invalid_json",
          "body" => inspect(reason)
        }
      ]
    }
  end

  defp run_request_opts(assignment, opts) do
    [
      cwd: workspace_root(assignment, opts),
      model: Keyword.get(opts, :model),
      timeout_ms: Keyword.get(opts, :timeout_ms),
      allowed_tools: ExecutionContract.allowed_tools(assignment, opts)
    ]
  end

  defp driver_opts(assignment, opts) do
    opts
    |> Keyword.get(:driver_opts, [])
    |> Keyword.put_new(:scenario, scenario_from_assignment(assignment))
    |> Keyword.put_new(:reasoning_effort, Keyword.get(opts, :reasoning_effort, :low))
  end

  defp scenario_from_assignment(assignment) do
    case Map.get(assignment, "phase") do
      "critique" -> :skeptic
      "resolution" -> :resolver
      "analysis" -> :analyst
      _other -> :architect
    end
  end

  defp default_model(:codex), do: "gpt-5.4"
  defp default_model(_provider), do: nil

  defp repair_response(session, assignment, run, opts, text) do
    case RepairPolicy.attempt_repair?(opts, text) do
      true ->
        Status.repair_started(assignment, :invalid_contribution_json, text)

        request =
          CollaborationPrompt.to_repair_run_request(
            text,
            assignment,
            RepairPolicy.request_opts(assignment, opts)
          )

        run_repair(session, request, run, assignment, opts)

      false ->
        :error
    end
  end

  defp run_repair(session, request, run, assignment, opts) do
    case Harness.stream_run(session, request,
           run_id: "#{run.run_id}-repair",
           driver: Keyword.get(opts, :driver),
           driver_opts: driver_opts(assignment, opts)
         ) do
      {:ok, repair_run, repair_stream} ->
        repair_events = Enum.to_list(repair_stream)
        repair_projection = Projection.build(repair_events, repair_run, session)

        Status.repair_finished(assignment, repair_projection.execution["text"])
        decode_repair_projection(assignment, repair_events, repair_projection)

      {:error, _} = error ->
        Status.repair_failed(assignment, error)
        :error
    end
  end

  defp decode_repair_projection(assignment, repair_events, repair_projection) do
    case ResultDecoder.decode(repair_projection.execution["text"]) do
      {:ok, decoded_payload} ->
        {:ok, repair_events, repair_projection, decoded_payload}

      {:error, reason} ->
        Status.repair_failed(assignment, reason)
        :error
    end
  end
end
