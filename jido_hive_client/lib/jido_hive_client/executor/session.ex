defmodule JidoHiveClient.Executor.Session do
  @moduledoc false

  @behaviour JidoHiveClient.Executor

  alias Jido.Harness
  alias Jido.Harness.ExecutionEvent
  alias JidoHiveClient.{CollaborationPrompt, ExecutionContract, ResultDecoder, Status}
  alias JidoHiveClient.Executor.{Projection, RepairPolicy}

  @runtime_id :asm

  @impl true
  def run(job, opts) when is_map(job) and is_list(opts) do
    opts = ExecutionContract.apply_session_defaults(job, opts)
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
      ExecutionContract.start_session_opts(job, opts, provider, session_id)

    Status.execution_started(
      job,
      Keyword.merge(opts, provider: provider, model: model, reasoning_effort: reasoning_effort),
      request
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
    projection = Projection.build(events, run, session)

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
          Projection.merge_repair(projection, repair_projection, reason),
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
    ExecutionContract.workspace_root(job, opts)
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
      allowed_tools: ExecutionContract.allowed_tools(job, opts)
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

  defp repair_response(session, job, run, opts, text) do
    case RepairPolicy.attempt_repair?(opts, text) do
      true ->
        Status.repair_started(job, :invalid_collaboration_json, text)

        request =
          CollaborationPrompt.to_repair_run_request(
            text,
            job,
            RepairPolicy.request_opts(job, opts)
          )

        run_repair(session, request, run, job, opts)

      false ->
        :error
    end
  end

  defp run_repair(session, request, run, job, opts) do
    case Harness.stream_run(session, request,
           run_id: "#{run.run_id}-repair",
           driver: Keyword.get(opts, :driver),
           driver_opts: driver_opts(job, opts)
         ) do
      {:ok, repair_run, repair_stream} ->
        repair_events = Enum.to_list(repair_stream)
        repair_projection = Projection.build(repair_events, repair_run, session)

        Status.repair_finished(job, repair_projection.execution["text"])
        decode_repair_projection(job, repair_events, repair_projection)

      {:error, _} = error ->
        Status.repair_failed(job, error)
        :error
    end
  end

  defp decode_repair_projection(job, repair_events, repair_projection) do
    case ResultDecoder.decode(repair_projection.execution["text"]) do
      {:ok, decoded_payload} ->
        {:ok, repair_events, repair_projection, decoded_payload}

      {:error, reason} ->
        Status.repair_failed(job, reason)
        :error
    end
  end
end
