defmodule JidoHiveWorkerRuntime.Status do
  @moduledoc false

  @system_prompt_preview_limit 220
  @prompt_preview_limit 320
  @response_preview_limit 320

  def client_start(opts) when is_list(opts) do
    emit(
      "starting participant=#{opts[:participant_id]} role=#{opts[:participant_role]} " <>
        "target=#{opts[:target_id]} provider=#{provider_label(opts[:executor])} " <>
        "workspace=#{opts[:workspace_id]} url=#{opts[:url]}"
    )
  end

  def relay_ready(state) when is_map(state) do
    room_ids = state |> Map.get(:room_channels, %{}) |> Map.keys() |> Enum.sort()

    emit(
      "ready participant=#{state.participant_id} role=#{state.participant_role} " <>
        "target=#{state.target_id} capability=#{state.capability_id} " <>
        "workspace=#{state.workspace_id} url=#{state.socket_url} " <>
        "rooms=#{Enum.join(room_ids, ",")} waiting_for=assignment.offer " <>
        "services=phoenix-room+jido-harness+asm+#{provider_label(state.executor)}"
    )
  end

  def relay_connecting(state) when is_map(state) do
    emit(
      "connecting participant=#{state.participant_id} role=#{state.participant_role} " <>
        "target=#{state.target_id} workspace=#{state.workspace_id} " <>
        "url=#{state.socket_url}"
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
        "url=#{state.socket_url} reason=#{inspect(reason)}"
    )
  end

  def relay_disconnected(state, event) when is_map(state) do
    emit(
      "relay disconnected participant=#{state.participant_id} target=#{state.target_id} " <>
        "event=#{event} url=#{state.socket_url}"
    )
  end

  def assignment_received(assignment, state) when is_map(assignment) and is_map(state) do
    assigned_role = Map.get(assignment, "participant_role", state.participant_role)

    emit(
      "assignment received room=#{assignment["room_id"]} phase=#{phase(assignment)} client=#{state.participant_id} " <>
        "assigned_role=#{assigned_role} objective=\"#{truncate(objective(assignment), 120)}\""
    )
  end

  def execution_started(assignment, opts, request)
      when is_map(assignment) and is_list(opts) and is_map(request) do
    assigned_role =
      Map.get(assignment, "participant_role", Keyword.get(opts, :participant_role, "worker"))

    emit(
      "executing room=#{assignment["room_id"]} phase=#{phase(assignment)} provider=#{provider_label(opts[:provider])} " <>
        "assigned_role=#{assigned_role} model=#{opts[:model] || "default"} " <>
        "reasoning=#{opts[:reasoning_effort] || "default"} runtime=asm path=jido.harness->asm"
    )

    emit_preview(
      "system prompt",
      assignment,
      Map.get(request, :system_prompt),
      @system_prompt_preview_limit
    )

    emit_preview("user prompt", assignment, Map.get(request, :prompt), @prompt_preview_limit)
  end

  def repair_started(assignment, reason, invalid_text) when is_map(assignment) do
    emit(
      "repair pass room=#{assignment["room_id"]} phase=#{phase(assignment)} " <>
        "reason=#{inspect(reason)}"
    )

    emit_preview("invalid response", assignment, invalid_text, @response_preview_limit)
  end

  def repair_finished(assignment, repair_text) when is_map(assignment) do
    emit_preview("repair response", assignment, repair_text, @response_preview_limit)
  end

  def repair_failed(assignment, reason) when is_map(assignment) do
    emit(
      "repair failed room=#{assignment["room_id"]} phase=#{phase(assignment)} " <>
        "reason=#{inspect(reason)}"
    )
  end

  def execution_finished(assignment, contribution)
      when is_map(assignment) and is_map(contribution) do
    emit_preview(
      "response",
      assignment,
      get_in(contribution, ["execution", "text"]),
      @response_preview_limit
    )

    emit(
      "completed room=#{assignment["room_id"]} phase=#{phase(assignment)} status=#{contribution["status"]} " <>
        "contribution=#{contribution["kind"] || "none"}#{usage_summary(contribution)}"
    )
  end

  def execution_failed(assignment, reason) when is_map(assignment) do
    emit(
      "execution failed room=#{assignment["room_id"]} phase=#{phase(assignment)} " <>
        "reason=#{inspect(reason)}"
    )
  end

  def result_published(assignment, contribution)
      when is_map(assignment) and is_map(contribution) do
    emit(
      "contribution published room=#{assignment["room_id"]} phase=#{phase(assignment)} status=#{contribution_status(contribution)}"
    )
  end

  defp emit(message) do
    IO.puts("#{timestamp()} [jido_hive worker] #{message}")
  end

  defp timestamp do
    unix_ms = System.os_time(:millisecond)
    unix_seconds = div(unix_ms, 1_000)
    millisecond = rem(unix_ms, 1_000)

    {hour, minute, second} =
      unix_seconds
      |> :calendar.system_time_to_universal_time(:second)
      |> :calendar.universal_time_to_local_time()
      |> then(fn {{_year, _month, _day}, {hour, minute, second}} ->
        {hour, minute, second}
      end)

    :io_lib.format("~2..0B:~2..0B:~2..0B.~3..0B", [hour, minute, second, millisecond])
    |> IO.iodata_to_binary()
  end

  defp emit_preview(_label, _assignment, nil, _limit), do: :ok

  defp emit_preview(label, assignment, text, limit) when is_binary(text) do
    preview = preview_text(text, limit)

    emit(
      "#{label} preview room=#{assignment["room_id"]} phase=#{phase(assignment)} " <>
        "bytes=#{byte_size(text)} preview=#{inspect(preview)}"
    )
  end

  defp emit_preview(_label, _assignment, _text, _limit), do: :ok

  defp phase(assignment) do
    Map.get(assignment, "phase") || "unknown"
  end

  defp objective(assignment) do
    Map.get(assignment, "objective") || "unknown"
  end

  defp preview_text(text, limit) do
    trimmed =
      text
      |> String.trim()
      |> String.replace(~r/\s+/, " ")

    cond do
      trimmed == "" ->
        "(empty)"

      String.length(trimmed) <= limit ->
        trimmed

      true ->
        String.slice(trimmed, 0, limit - 1) <> "…"
    end
  end

  defp truncate(nil, _limit), do: "unknown"
  defp truncate(value, limit) when byte_size(value) <= limit, do: value
  defp truncate(value, limit), do: String.slice(value, 0, limit - 3) <> "..."

  defp provider_label({_, opts}) when is_list(opts), do: provider_label(opts[:provider])
  defp provider_label(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp provider_label(provider) when is_binary(provider), do: provider
  defp provider_label(_other), do: "codex"

  defp usage_summary(contribution) do
    cost = get_in(contribution, ["execution", "cost"]) || %{}

    input_tokens = Map.get(cost, "input_tokens")
    output_tokens = Map.get(cost, "output_tokens")

    if is_integer(input_tokens) and is_integer(output_tokens) do
      " tokens=#{input_tokens}/#{output_tokens}"
    else
      ""
    end
  end

  defp contribution_status(contribution) do
    contribution["status"] || get_in(contribution, ["meta", "status"]) || ""
  end
end
