defmodule JidoHiveTermuiConsole.EventLogPoller do
  @moduledoc false

  @poll_interval_ms 2_000

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    app_pid = Keyword.fetch!(opts, :app_pid)
    api_base_url = Keyword.get(opts, :api_base_url, "http://127.0.0.1:4000/api")
    cursor = Keyword.get(opts, :cursor)
    operator_module = Keyword.get(opts, :operator_module, JidoHiveClient.Operator)
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, @poll_interval_ms)

    Task.start_link(fn ->
      loop(
        room_id,
        app_pid,
        api_base_url,
        operator_module,
        cursor,
        MapSet.new(),
        0,
        poll_interval_ms
      )
    end)
  end

  defp loop(
         room_id,
         app_pid,
         api_base_url,
         operator_module,
         cursor,
         seen_ids,
         failures,
         interval_ms
       ) do
    Process.sleep(interval_ms)

    {next_cursor, next_seen_ids, next_failures} =
      operator_module.fetch_room_timeline(api_base_url, room_id, after: cursor)
      |> handle_poll_response(app_pid, cursor, seen_ids, failures)

    loop(
      room_id,
      app_pid,
      api_base_url,
      operator_module,
      next_cursor,
      next_seen_ids,
      next_failures,
      interval_ms
    )
  end

  defp dedupe_entries(entries, seen_ids) do
    Enum.reduce(entries, {[], seen_ids}, &dedupe_entry/2)
  end

  defp trim_seen_ids(seen_ids) do
    if MapSet.size(seen_ids) > 500 do
      seen_ids
      |> Enum.take(-250)
      |> MapSet.new()
    else
      seen_ids
    end
  end

  defp last_cursor(entries) do
    entries
    |> List.last()
    |> then(fn
      nil -> nil
      entry -> Map.get(entry, "cursor") || Map.get(entry, :cursor)
    end)
  end

  defp entry_identity(entry) do
    Map.get(entry, "cursor") || Map.get(entry, :cursor) ||
      Map.get(entry, "entry_id") || Map.get(entry, :entry_id) ||
      Map.get(entry, "event_id") || Map.get(entry, :event_id)
  end

  defp handle_poll_response(
         {:ok, %{entries: entries, next_cursor: next_cursor}},
         app_pid,
         cursor,
         seen_ids,
         _failures
       )
       when is_list(entries) do
    {deduped, next_seen_ids} = dedupe_entries(entries, seen_ids)
    resolved_cursor = next_cursor || last_cursor(deduped) || cursor
    maybe_send_update(app_pid, deduped, resolved_cursor)
    {resolved_cursor, next_seen_ids, 0}
  end

  defp handle_poll_response({:error, reason}, app_pid, cursor, seen_ids, failures) do
    maybe_send_warning(app_pid, failures + 1, reason)
    {cursor, seen_ids, failures + 1}
  end

  defp handle_poll_response(_other, _app_pid, cursor, seen_ids, failures) do
    {cursor, seen_ids, failures}
  end

  defp maybe_send_update(_app_pid, [], _cursor), do: :ok

  defp maybe_send_update(app_pid, deduped, cursor) do
    send(app_pid, {:event_log_update, deduped, cursor})
  end

  defp maybe_send_warning(_app_pid, failures, _reason) when failures < 3, do: :ok

  defp maybe_send_warning(app_pid, _failures, reason),
    do: send(app_pid, {:event_log_warning, reason})

  defp dedupe_entry(entry, {acc, seen_ids}) do
    id = entry_identity(entry)

    if duplicate_entry?(id, seen_ids) do
      {acc, seen_ids}
    else
      {acc ++ [entry], remember_seen_id(seen_ids, id)}
    end
  end

  defp duplicate_entry?(nil, _seen_ids), do: false
  defp duplicate_entry?(id, seen_ids), do: MapSet.member?(seen_ids, id)

  defp remember_seen_id(seen_ids, nil), do: seen_ids

  defp remember_seen_id(seen_ids, id) do
    seen_ids
    |> MapSet.put(id)
    |> trim_seen_ids()
  end
end
