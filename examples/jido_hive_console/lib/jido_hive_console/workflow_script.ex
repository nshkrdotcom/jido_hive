defmodule JidoHiveConsole.WorkflowScript do
  @moduledoc false

  alias JidoHiveClient.HeadlessCLI

  @default_api_base_url "http://127.0.0.1:4000/api"
  @default_brief "Workflow smoke room"
  @default_participant_role "coordinator"
  @default_authority_level "binding"

  @switches [
    api_base_url: :string,
    room_id: :string,
    brief: :string,
    participant_id: :string,
    participant_role: :string,
    authority_level: :string,
    text: :keep,
    run: :boolean,
    max_assignments: :integer,
    assignment_timeout_ms: :integer
  ]

  @spec run([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def run(argv, opts \\ []) when is_list(argv) and is_list(opts) do
    headless_module = Keyword.get(opts, :headless_module, HeadlessCLI)

    with {:ok, parsed} <- parse_args(argv) do
      api_base_url = Keyword.get(parsed, :api_base_url) || Keyword.get(opts, :api_base_url) || @default_api_base_url
      room_id = Keyword.get(parsed, :room_id) || generated_room_id()
      brief = Keyword.get(parsed, :brief, @default_brief)
      participant_id = Keyword.get(parsed, :participant_id, "alice")
      participant_role = Keyword.get(parsed, :participant_role, @default_participant_role)
      authority_level = Keyword.get(parsed, :authority_level, @default_authority_level)
      texts = Keyword.get_values(parsed, :text)

      payload_path = write_room_payload(room_id, brief)

      try do
        with {:ok, created} <-
               dispatch(headless_module, room_create_args(api_base_url, payload_path), opts),
             {:ok, initial_room} <-
               dispatch(headless_module, room_show_args(api_base_url, room_id), opts),
             {:ok, submissions} <-
               run_submissions(
                 headless_module,
                 api_base_url,
                 room_id,
                 participant_id,
                 participant_role,
                 authority_level,
                 texts,
                 opts
               ),
             {:ok, run_result} <- maybe_run_room(headless_module, api_base_url, room_id, parsed, opts),
             {:ok, final_room} <-
               dispatch(headless_module, room_show_args(api_base_url, room_id), opts),
             {:ok, timeline} <-
               dispatch(headless_module, room_timeline_args(api_base_url, room_id), opts) do
          {:ok,
           %{
             "workflow" => "room_smoke",
             "api_base_url" => api_base_url,
             "room_id" => room_id,
             "brief" => brief,
             "participant_id" => participant_id,
             "created" => created,
             "initial_room" => initial_room,
             "submissions" => submissions,
             "run" => run_result,
             "final_room" => final_room,
             "timeline" => timeline
           }}
        end
      after
        File.rm(payload_path)
      end
    end
  end

  defp parse_args(argv) do
    {parsed, rest, invalid} = OptionParser.parse(argv, strict: @switches)

    cond do
      invalid != [] ->
        {:error, {:invalid_options, invalid}}

      rest != [] ->
        {:error, {:unexpected_arguments, rest}}

      true ->
        {:ok, parsed}
    end
  end

  defp room_create_args(api_base_url, payload_path) do
    [
      "room",
      "create",
      "--api-base-url",
      api_base_url,
      "--payload-file",
      payload_path
    ]
  end

  defp room_show_args(api_base_url, room_id) do
    ["room", "show", "--api-base-url", api_base_url, "--room-id", room_id]
  end

  defp room_timeline_args(api_base_url, room_id) do
    ["room", "timeline", "--api-base-url", api_base_url, "--room-id", room_id]
  end

  defp room_submit_args(
         api_base_url,
         room_id,
         participant_id,
         participant_role,
         authority_level,
         text
       ) do
    [
      "room",
      "submit",
      "--api-base-url",
      api_base_url,
      "--room-id",
      room_id,
      "--participant-id",
      participant_id,
      "--participant-role",
      participant_role,
      "--authority-level",
      authority_level,
      "--text",
      text
    ]
  end

  defp room_run_args(api_base_url, room_id, parsed) do
    [
      "room",
      "run",
      "--api-base-url",
      api_base_url,
      "--room-id",
      room_id
    ]
    |> maybe_append_integer_flag("--max-assignments", Keyword.get(parsed, :max_assignments))
    |> maybe_append_integer_flag(
      "--assignment-timeout-ms",
      Keyword.get(parsed, :assignment_timeout_ms)
    )
  end

  defp run_submissions(
         headless_module,
         api_base_url,
         room_id,
         participant_id,
         participant_role,
         authority_level,
         texts,
         opts
       ) do
    texts
    |> Enum.reduce_while({:ok, []}, fn text, {:ok, acc} ->
      with {:ok, submit_result} <-
             dispatch(
               headless_module,
               room_submit_args(
                 api_base_url,
                 room_id,
                 participant_id,
                 participant_role,
                 authority_level,
                 text
               ),
               opts
             ),
           {:ok, room_after_submit} <-
             dispatch(headless_module, room_show_args(api_base_url, room_id), opts) do
        {:cont,
         {:ok,
          acc ++
            [
              %{
                "text" => text,
                "submit" => submit_result,
                "room_after_submit" => room_after_submit
              }
            ]}}
      else
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp maybe_run_room(headless_module, api_base_url, room_id, parsed, opts) do
    if Keyword.get(parsed, :run, false) do
      dispatch(headless_module, room_run_args(api_base_url, room_id, parsed), opts)
    else
      {:ok, nil}
    end
  end

  defp dispatch(headless_module, argv, opts) do
    dispatch_opts =
      opts
      |> Keyword.drop([:headless_module, :api_base_url])

    headless_module.dispatch(argv, dispatch_opts)
  end

  defp write_room_payload(room_id, brief) do
    payload_path =
      Path.join(
        System.tmp_dir!(),
        "jido_hive_console_room_smoke_#{System.unique_integer([:positive])}.json"
      )

    payload = %{
      "room_id" => room_id,
      "brief" => brief,
      "participants" => []
    }

    File.write!(payload_path, Jason.encode!(payload, pretty: true))
    payload_path
  end

  defp generated_room_id do
    "room-smoke-#{System.unique_integer([:positive])}"
  end

  defp maybe_append_integer_flag(args, _flag, nil), do: args
  defp maybe_append_integer_flag(args, _flag, value) when not is_integer(value), do: args
  defp maybe_append_integer_flag(args, flag, value), do: args ++ [flag, Integer.to_string(value)]
end
