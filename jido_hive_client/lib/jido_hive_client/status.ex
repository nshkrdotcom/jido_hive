defmodule JidoHiveClient.Status do
  @moduledoc false

  @system_prompt_preview_limit 700
  @prompt_preview_limit 1_600
  @response_preview_limit 1_600

  def client_start(opts) when is_list(opts) do
    emit(
      "starting participant=#{opts[:participant_id]} role=#{opts[:participant_role]} " <>
        "target=#{opts[:target_id]} provider=#{provider_label(opts[:executor])} " <>
        "relay=#{opts[:relay_topic]} workspace=#{opts[:workspace_id]} " <>
        "url=#{opts[:url]}"
    )
  end

  def relay_ready(state) when is_map(state) do
    emit(
      "ready participant=#{state.participant_id} role=#{state.participant_role} " <>
        "target=#{state.target_id} capability=#{state.capability_id} " <>
        "relay=#{state.relay_topic} workspace=#{state.workspace_id} " <>
        "url=#{state.socket_url} waiting_for=job.start " <>
        "services=phoenix-relay+jido-harness+asm+#{provider_label(state.executor)}"
    )
  end

  def relay_connecting(state) when is_map(state) do
    emit(
      "connecting participant=#{state.participant_id} role=#{state.participant_role} " <>
        "target=#{state.target_id} relay=#{state.relay_topic} " <>
        "workspace=#{state.workspace_id} url=#{state.socket_url}"
    )
  end

  def relay_waiting(state) when is_map(state) do
    emit(
      "waiting for websocket participant=#{state.participant_id} target=#{state.target_id} " <>
        "url=#{state.socket_url}"
    )
  end

  def relay_join_retry(state, reason) when is_map(state) do
    emit(
      "join retry participant=#{state.participant_id} target=#{state.target_id} " <>
        "topic=#{state.relay_topic} url=#{state.socket_url} reason=#{inspect(reason)}"
    )
  end

  def relay_disconnected(state, event) when is_map(state) do
    emit(
      "relay disconnected participant=#{state.participant_id} target=#{state.target_id} " <>
        "event=#{event} url=#{state.socket_url}"
    )
  end

  def job_received(job, state) when is_map(job) and is_map(state) do
    emit(
      "job received room=#{job["room_id"]} phase=#{phase(job)} role=#{state.participant_role} " <>
        "objective=\"#{truncate(objective(job), 120)}\""
    )
  end

  def execution_started(job, opts, request)
      when is_map(job) and is_list(opts) and is_map(request) do
    emit(
      "executing room=#{job["room_id"]} phase=#{phase(job)} provider=#{provider_label(opts[:provider])} " <>
        "model=#{opts[:model] || "default"} reasoning=#{opts[:reasoning_effort] || "default"} " <>
        "runtime=asm path=jido.harness->asm"
    )

    emit_preview(
      "system prompt",
      job,
      Map.get(request, :system_prompt),
      @system_prompt_preview_limit
    )

    emit_preview("user prompt", job, Map.get(request, :prompt), @prompt_preview_limit)
  end

  def repair_started(job, reason, invalid_text) when is_map(job) do
    emit(
      "repair pass room=#{job["room_id"]} phase=#{phase(job)} " <>
        "reason=#{inspect(reason)}"
    )

    emit_preview("invalid response", job, invalid_text, @response_preview_limit)
  end

  def repair_finished(job, repair_text) when is_map(job) do
    emit_preview("repair response", job, repair_text, @response_preview_limit)
  end

  def repair_failed(job, reason) when is_map(job) do
    emit(
      "repair failed room=#{job["room_id"]} phase=#{phase(job)} " <>
        "reason=#{inspect(reason)}"
    )
  end

  def execution_finished(job, result) when is_map(job) and is_map(result) do
    emit_preview("response", job, get_in(result, ["execution", "text"]), @response_preview_limit)

    emit(
      "completed room=#{job["room_id"]} phase=#{phase(job)} status=#{result["status"]} " <>
        "actions=#{action_summary(result["actions"])}#{usage_summary(result)}"
    )
  end

  def execution_failed(job, reason) when is_map(job) do
    emit(
      "execution failed room=#{job["room_id"]} phase=#{phase(job)} " <>
        "reason=#{inspect(reason)}"
    )
  end

  def result_published(job, result) when is_map(job) and is_map(result) do
    emit("result published room=#{job["room_id"]} phase=#{phase(job)} status=#{result["status"]}")
  end

  defp emit(message) do
    IO.puts("[jido_hive client] #{message}")
  end

  defp emit_preview(_label, _job, nil, _limit), do: :ok

  defp emit_preview(label, job, text, limit) when is_binary(text) do
    preview = preview_text(text, limit)

    emit(
      "#{label} preview room=#{job["room_id"]} phase=#{phase(job)} " <>
        "bytes=#{byte_size(text)}"
    )

    preview
    |> String.split("\n")
    |> Enum.each(&emit("  #{&1}"))
  end

  defp emit_preview(_label, _job, _text, _limit), do: :ok

  defp phase(job) do
    get_in(job, ["collaboration_envelope", "turn", "phase"]) || "unknown"
  end

  defp objective(job) do
    get_in(job, ["collaboration_envelope", "turn", "objective"]) || "unknown"
  end

  defp preview_text(text, limit) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        "(empty)"

      String.length(trimmed) <= limit ->
        trimmed

      true ->
        String.slice(trimmed, 0, limit) <> "\n...[truncated]"
    end
  end

  defp truncate(nil, _limit), do: "unknown"
  defp truncate(value, limit) when byte_size(value) <= limit, do: value
  defp truncate(value, limit), do: String.slice(value, 0, limit - 3) <> "..."

  defp provider_label({_, opts}) when is_list(opts), do: provider_label(opts[:provider])
  defp provider_label(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp provider_label(provider) when is_binary(provider), do: provider
  defp provider_label(_other), do: "codex"

  defp action_summary(actions) when is_list(actions) do
    actions
    |> Enum.map(&(Map.get(&1, "op") || Map.get(&1, :op) || "unknown"))
    |> Enum.uniq()
    |> case do
      [] -> "none"
      ops -> Enum.join(ops, ",")
    end
  end

  defp action_summary(_other), do: "none"

  defp usage_summary(result) do
    cost = get_in(result, ["execution", "cost"]) || %{}

    input_tokens = Map.get(cost, "input_tokens")
    output_tokens = Map.get(cost, "output_tokens")

    if is_integer(input_tokens) and is_integer(output_tokens) do
      " tokens=#{input_tokens}/#{output_tokens}"
    else
      ""
    end
  end
end
