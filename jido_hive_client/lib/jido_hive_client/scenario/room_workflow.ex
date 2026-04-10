defmodule JidoHiveClient.Scenario.RoomWorkflow do
  @moduledoc """
  Non-TUI room workflow harness for integration and regression testing.
  """

  alias JidoHiveClient.RoomWorkflow, as: SharedRoomWorkflow

  @default_poll_interval_ms 100
  @default_max_wait_ms 5_000

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts) when is_list(opts) do
    api_base_url = Keyword.fetch!(opts, :api_base_url)
    room_payload = Keyword.fetch!(opts, :room_payload)
    room_id = Map.fetch!(room_payload, "room_id")
    participant_id = Keyword.fetch!(opts, :participant_id)
    participant_role = Keyword.get(opts, :participant_role, "coordinator")
    before_run_text = Keyword.fetch!(opts, :before_run_text)
    during_run_text = Keyword.fetch!(opts, :during_run_text)
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)
    max_wait_ms = Keyword.get(opts, :max_wait_ms, @default_max_wait_ms)
    run_opts = Keyword.get(opts, :run_opts, [])

    {operator_module, operator_opts} =
      delegate(Keyword.get(opts, :operator, JidoHiveClient.Operator))

    {session_module, session_opts} =
      delegate(Keyword.get(opts, :session, JidoHiveClient.Embedded))

    with {:ok, room} <-
           invoke_operator(operator_module, operator_opts, :create_room, [
             api_base_url,
             room_payload
           ]),
         {:ok, session} <-
           session_module.start_link(
             [
               api_base_url: api_base_url,
               room_id: room_id,
               participant_id: participant_id,
               participant_role: participant_role
             ] ++
               session_opts
           ) do
      try do
        with {:ok, _initial_snapshot} <- session_module.refresh(session),
             {:ok, before_run_submit} <-
               session_module.submit_chat(session, %{text: before_run_text}),
             {:ok, run_operation} <-
               invoke_operator(operator_module, operator_opts, :start_room_run_operation, [
                 api_base_url,
                 room_id,
                 run_opts
               ]),
             {:ok, during_run_submit} <-
               session_module.submit_chat(session, %{text: during_run_text}),
             {:ok, completed_run_operation} <-
               wait_for_run_completion(
                 operator_module,
                 operator_opts,
                 api_base_url,
                 room_id,
                 run_operation["operation_id"],
                 poll_interval_ms,
                 max_wait_ms
               ),
             {:ok, final_sync} <-
               invoke_operator(operator_module, operator_opts, :fetch_room_sync, [
                 api_base_url,
                 room_id,
                 []
               ]) do
          workflow_summary = SharedRoomWorkflow.summary(final_sync.room_snapshot)

          {:ok,
           %{
             room: room,
             before_run_submit: before_run_submit,
             during_run_submit: during_run_submit,
             run_operation: completed_run_operation,
             final_sync: final_sync,
             workflow_summary: workflow_summary,
             transitions: [
               :room_created,
               :room_refreshed,
               :chat_submitted_before_run,
               :run_started,
               :chat_submitted_during_run,
               :run_completed,
               :room_synced
             ]
           }}
        end
      after
        shutdown_session(session_module, session)
      end
    end
  end

  defp wait_for_run_completion(
         operator_module,
         operator_opts,
         api_base_url,
         room_id,
         operation_id,
         poll_interval_ms,
         max_wait_ms
       ) do
    deadline = System.monotonic_time(:millisecond) + max_wait_ms

    do_wait_for_run_completion(
      operator_module,
      operator_opts,
      api_base_url,
      room_id,
      operation_id,
      poll_interval_ms,
      deadline
    )
  end

  defp do_wait_for_run_completion(
         operator_module,
         operator_opts,
         api_base_url,
         room_id,
         operation_id,
         poll_interval_ms,
         deadline_ms
       ) do
    case invoke_operator(operator_module, operator_opts, :fetch_room_run_operation, [
           api_base_url,
           room_id,
           operation_id,
           []
         ]) do
      {:ok, %{"status" => status} = operation} when status in ["completed", "failed"] ->
        {:ok, operation}

      {:ok, _operation} ->
        if System.monotonic_time(:millisecond) >= deadline_ms do
          {:error, :timeout}
        else
          Process.sleep(poll_interval_ms)

          do_wait_for_run_completion(
            operator_module,
            operator_opts,
            api_base_url,
            room_id,
            operation_id,
            poll_interval_ms,
            deadline_ms
          )
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp shutdown_session(session_module, session) do
    if function_exported?(session_module, :shutdown, 1) do
      _ = session_module.shutdown(session)
    else
      _ = GenServer.stop(session)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end

  defp delegate({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}
  defp delegate(module) when is_atom(module), do: {module, []}

  defp invoke_operator(module, opts, function_name, args) do
    cond do
      function_exported?(module, function_name, length(args) + 1) ->
        apply(module, function_name, args ++ [opts])

      merge_operator_opts?(opts, args) and function_exported?(module, function_name, length(args)) ->
        merged_args = List.update_at(args, -1, &Keyword.merge(&1, opts))
        apply(module, function_name, merged_args)

      function_exported?(module, function_name, length(args)) ->
        apply(module, function_name, args)

      true ->
        {:error, {:undefined_operator_function, module, function_name, length(args)}}
    end
  end

  defp merge_operator_opts?([_ | _], [_ | _] = args), do: is_list(List.last(args))
  defp merge_operator_opts?(_opts, _args), do: false
end
