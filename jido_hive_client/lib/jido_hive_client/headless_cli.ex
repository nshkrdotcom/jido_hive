defmodule JidoHiveClient.HeadlessCLI do
  @moduledoc """
  Headless operator and session commands for scripting `jido_hive_client`.
  """

  alias JidoHiveClient.{Operation, Operator, RoomSession, RoomWorkflow}

  @operator_switches [
    api_base_url: :string,
    room_id: :string,
    payload_file: :string,
    subject: :string,
    participant_id: :string,
    participant_role: :string,
    authority_level: :string,
    after: :string,
    channel: :string,
    install_id: :string,
    operation_id: :string,
    access_token: :string,
    left: :string,
    right: :string,
    text: :string,
    scope: :string,
    max_assignments: :integer,
    assignment_timeout_ms: :integer,
    request_timeout_ms: :integer,
    connect_timeout_ms: :integer
  ]

  @session_switches [
    api_base_url: :string,
    room_id: :string,
    participant_id: :string,
    participant_role: :string,
    authority_level: :string,
    poll_interval_ms: :integer,
    text: :string,
    context_id: :string,
    selected_context_id: :string,
    selected_context_object_type: :string,
    selected_relation: :string
  ]

  @spec dispatch([String.t()], keyword()) :: {:ok, term()} | {:error, term()}
  def dispatch(argv, opts \\ []) when is_list(argv) and is_list(opts) do
    operator_module = Keyword.get(opts, :operator_module, Operator)
    embedded_module = Keyword.get(opts, :embedded_module, RoomSession)

    maybe_ensure_initialized(operator_module)

    config = operator_module.load_config()

    argv
    |> normalize_argv()
    |> dispatch_command(config, operator_module, embedded_module)
  end

  defp normalize_argv(["config", "show" | rest]), do: ["operator", "config", "show" | rest]
  defp normalize_argv(["rooms", "list" | rest]), do: ["operator", "rooms", "list" | rest]
  defp normalize_argv(["targets", "list" | rest]), do: ["operator", "targets", "list" | rest]
  defp normalize_argv(["policies", "list" | rest]), do: ["operator", "policies", "list" | rest]
  defp normalize_argv(["auth", "state" | rest]), do: ["operator", "auth", "state" | rest]

  defp normalize_argv(["auth", "install", "start" | rest]),
    do: ["operator", "auth", "start-install" | rest]

  defp normalize_argv(["auth", "install", "complete" | rest]),
    do: ["operator", "auth", "complete-install" | rest]

  defp normalize_argv(["room", "list" | rest]), do: ["operator", "rooms", "list" | rest]
  defp normalize_argv(["room", "show" | rest]), do: ["operator", "room", "get" | rest]
  defp normalize_argv(["room", "get" | rest]), do: ["operator", "room", "get" | rest]
  defp normalize_argv(["room", "workflow" | rest]), do: ["operator", "room", "workflow" | rest]
  defp normalize_argv(["room", "inspect" | rest]), do: ["operator", "room", "inspect" | rest]

  defp normalize_argv(["room", "publish-plan" | rest]),
    do: ["operator", "room", "publish-plan" | rest]

  defp normalize_argv(["room", "tail" | rest]), do: ["operator", "room", "timeline" | rest]
  defp normalize_argv(["room", "timeline" | rest]), do: ["operator", "room", "timeline" | rest]
  defp normalize_argv(["room", "create" | rest]), do: ["operator", "room", "create" | rest]
  defp normalize_argv(["room", "run" | rest]), do: ["operator", "room", "run" | rest]

  defp normalize_argv(["room", "run-status" | rest]),
    do: ["operator", "room", "run-status" | rest]

  defp normalize_argv(["room", "publish" | rest]), do: ["operator", "room", "publish" | rest]
  defp normalize_argv(["room", "resolve" | rest]), do: ["operator", "room", "resolve" | rest]
  defp normalize_argv(["room", "submit" | rest]), do: ["session", "room", "submit-chat" | rest]
  defp normalize_argv(["room", "accept" | rest]), do: ["session", "room", "accept-context" | rest]
  defp normalize_argv(argv), do: argv

  defp dispatch_command(["operator" | rest], config, operator_module, _embedded_module) do
    dispatch_operator(rest, config, operator_module)
  end

  defp dispatch_command(["session" | rest], config, _operator_module, embedded_module) do
    dispatch_session(rest, config, embedded_module)
  end

  defp dispatch_command(_argv, _config, _operator_module, _embedded_module) do
    {:error, :unsupported_command}
  end

  defp dispatch_operator(["config", "show" | rest], config, _operator_module) do
    parse_command_opts(rest, [])
    |> then(fn
      {:ok, _parsed} -> {:ok, normalize_output(config)}
      error -> error
    end)
  end

  defp dispatch_operator(["rooms", "list" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config) do
      {:ok,
       normalize_output(%{
         "api_base_url" => api_base_url,
         "rooms" => operator_module.list_saved_rooms(api_base_url)
       })}
    end
  end

  defp dispatch_operator(["room", "get" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, room_id} <- required_option(parsed, :room_id),
         {:ok, room} <- operator_module.fetch_room(api_base_url, room_id) do
      {:ok, normalize_output(room)}
    end
  end

  defp dispatch_operator(["room", "workflow" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, room_id} <- required_option(parsed, :room_id),
         {:ok, sync_result} <-
           operator_module.fetch_room_sync(api_base_url, room_id, after: parsed[:after]) do
      {:ok,
       normalize_output(%{
         room_id: room_id,
         status: Map.get(sync_result.room_snapshot, "status"),
         workflow_summary: RoomWorkflow.summary(sync_result.room_snapshot)
       })}
    end
  end

  defp dispatch_operator(["room", "inspect" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, room_id} <- required_option(parsed, :room_id),
         {:ok, sync_result} <-
           operator_module.fetch_room_sync(api_base_url, room_id, after: parsed[:after]) do
      {:ok, normalize_output(RoomWorkflow.inspect_sync(sync_result))}
    end
  end

  defp dispatch_operator(["room", "publish-plan" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, room_id} <- required_option(parsed, :room_id),
         {:ok, publication_plan} <- operator_module.fetch_publication_plan(api_base_url, room_id) do
      {:ok, normalize_output(publication_plan)}
    end
  end

  defp dispatch_operator(["room", "timeline" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, room_id} <- required_option(parsed, :room_id),
         {:ok, timeline} <-
           operator_module.fetch_room_timeline(api_base_url, room_id, after: parsed[:after]) do
      {:ok, normalize_output(timeline)}
    end
  end

  defp dispatch_operator(["room", "create" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, payload_file} <- required_option(parsed, :payload_file),
         {:ok, payload} <- read_json_file(payload_file),
         {:ok, room} <- operator_module.create_room(api_base_url, payload),
         {:ok, room_id} <- room_id_from_payload(payload, room),
         :ok <- operator_module.add_saved_room(room_id, api_base_url) do
      {:ok, wrap_operation_result("room_create", room)}
    end
  end

  defp dispatch_operator(["room", "run" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, room_id} <- required_option(parsed, :room_id),
         {:ok, operation} <-
           operator_module.start_room_run_operation(api_base_url, room_id, room_run_opts(parsed)) do
      {:ok, normalize_output(operation)}
    end
  end

  defp dispatch_operator(["room", "run-status" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, room_id} <- required_option(parsed, :room_id),
         {:ok, operation_id} <- required_option(parsed, :operation_id),
         {:ok, operation} <-
           operator_module.fetch_room_run_operation(api_base_url, room_id, operation_id) do
      {:ok, normalize_output(operation)}
    end
  end

  defp dispatch_operator(["room", "publish" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, room_id} <- required_option(parsed, :room_id),
         {:ok, payload_file} <- required_option(parsed, :payload_file),
         {:ok, payload} <- read_json_file(payload_file),
         {:ok, result} <- operator_module.publish_room(api_base_url, room_id, payload) do
      {:ok, wrap_operation_result("room_publish", result)}
    end
  end

  defp dispatch_operator(["room", "resolve" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, room_id} <- required_option(parsed, :room_id),
         {:ok, left} <- required_option(parsed, :left),
         {:ok, right} <- required_option(parsed, :right),
         {:ok, text} <- required_option(parsed, :text),
         payload <- resolution_payload(parsed, config, room_id, left, right, text),
         {:ok, result} <- operator_module.submit_contribution(api_base_url, room_id, payload) do
      {:ok, wrap_operation_result("room_resolve", result)}
    end
  end

  defp dispatch_operator(["targets", "list" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, targets} <- operator_module.list_targets(api_base_url) do
      {:ok, normalize_output(targets)}
    end
  end

  defp dispatch_operator(["policies", "list" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, policies} <- operator_module.list_policies(api_base_url) do
      {:ok, normalize_output(policies)}
    end
  end

  defp dispatch_operator(["auth", "state" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, subject} <- required_option(parsed, :subject) do
      {:ok, normalize_output(operator_module.load_auth_state(api_base_url, subject))}
    end
  end

  defp dispatch_operator(["auth", "start-install" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, channel} <- required_option(parsed, :channel),
         {:ok, subject} <- required_option(parsed, :subject),
         scopes <- Keyword.get_values(parsed, :scope),
         {:ok, result} <- operator_module.start_install(api_base_url, channel, subject, scopes) do
      {:ok, normalize_output(result)}
    end
  end

  defp dispatch_operator(["auth", "complete-install" | rest], config, operator_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @operator_switches),
         api_base_url <- api_base_url(parsed, config),
         {:ok, install_id} <- required_option(parsed, :install_id),
         {:ok, subject} <- required_option(parsed, :subject),
         {:ok, access_token} <- required_option(parsed, :access_token),
         {:ok, result} <-
           operator_module.complete_install(api_base_url, install_id, subject, access_token) do
      {:ok, normalize_output(result)}
    end
  end

  defp dispatch_operator(_rest, _config, _operator_module), do: {:error, :unsupported_command}

  defp dispatch_session(["room", "snapshot" | rest], config, embedded_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @session_switches),
         {:ok, snapshot} <-
           with_room_session(parsed, config, embedded_module, fn session, _identity_opts ->
             {:ok, embedded_module.snapshot(session)}
           end) do
      {:ok, snapshot_response(snapshot, embedded_module)}
    end
  end

  defp dispatch_session(["room", "refresh" | rest], config, embedded_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @session_switches),
         {:ok, snapshot} <-
           with_room_session(parsed, config, embedded_module, fn session, _identity_opts ->
             embedded_module.refresh(session)
           end) do
      {:ok, snapshot_response(snapshot, embedded_module)}
    end
  end

  defp dispatch_session(["room", "submit-chat" | rest], config, embedded_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @session_switches),
         {:ok, text} <- required_option(parsed, :text),
         {:ok, result} <-
           with_room_session(parsed, config, embedded_module, fn session, identity_opts ->
             embedded_module.submit_chat(session, submit_chat_attrs(parsed, identity_opts, text))
           end) do
      {:ok, wrap_operation_result("room_submit", result)}
    end
  end

  defp dispatch_session(["room", "accept-context" | rest], config, embedded_module) do
    with {:ok, parsed} <- parse_command_opts(rest, @session_switches),
         {:ok, context_id} <- required_option(parsed, :context_id),
         {:ok, result} <-
           with_room_session(parsed, config, embedded_module, fn session, _identity_opts ->
             embedded_module.accept_context(session, context_id, %{})
           end) do
      {:ok, wrap_operation_result("room_accept", result)}
    end
  end

  defp dispatch_session(_rest, _config, _embedded_module), do: {:error, :unsupported_command}

  defp snapshot_response(snapshot, embedded_module) do
    normalize_output(%{
      snapshot: snapshot,
      sync_health: embedded_module.sync_health(snapshot)
    })
  end

  defp parse_command_opts(args, switches) do
    {parsed, rest, invalid} = OptionParser.parse(args, strict: switches)

    cond do
      invalid != [] ->
        {:error, {:invalid_options, invalid}}

      rest != [] ->
        {:error, {:unexpected_arguments, rest}}

      true ->
        {:ok, parsed}
    end
  end

  defp api_base_url(parsed, config) do
    Keyword.get(parsed, :api_base_url) || Map.get(config, "api_base_url") ||
      "http://127.0.0.1:4000/api"
  end

  defp required_option(opts, key) when is_list(opts) and is_atom(key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:missing_option, key}}
    end
  end

  defp read_json_file(path) when is_binary(path) do
    with {:ok, body} <- File.read(path),
         {:ok, payload} <- Jason.decode(body) do
      {:ok, payload}
    else
      {:error, reason} -> {:error, {:payload_file_error, path, reason}}
    end
  end

  defp room_id_from_payload(payload, room) do
    case Map.get(room, "room_id") || Map.get(payload, "room_id") do
      room_id when is_binary(room_id) and room_id != "" -> {:ok, room_id}
      _other -> {:error, :missing_room_id}
    end
  end

  defp resolution_payload(parsed, config, room_id, left, right, text) do
    identity = identity_opts(parsed, config)

    %{
      "room_id" => room_id,
      "participant_id" => identity.participant_id,
      "participant_role" => identity.participant_role,
      "participant_kind" => "human",
      "authority_level" => identity.authority_level,
      "execution" => %{"status" => "completed"},
      "status" => "completed",
      "contribution_type" => "decision",
      "summary" => "Resolution: #{text}",
      "context_objects" => [
        %{
          "object_type" => "decision",
          "title" => truncate(text, 72),
          "body" => text,
          "relations" => [
            %{"relation" => "resolves", "target_id" => left},
            %{"relation" => "resolves", "target_id" => right}
          ]
        }
      ]
    }
  end

  defp with_room_session(parsed, config, embedded_module, fun) when is_function(fun, 2) do
    with {:ok, room_id} <- required_option(parsed, :room_id),
         identity_opts <- identity_opts(parsed, config),
         session_opts <- session_start_opts(parsed, config, room_id, identity_opts),
         {:ok, session} <- embedded_module.start_link(session_opts) do
      try do
        fun.(session, identity_opts)
      after
        shutdown_session(embedded_module, session)
      end
    end
  end

  defp identity_opts(parsed, config) do
    participant_id =
      Keyword.get(parsed, :participant_id) || Map.get(config, "participant_id") ||
        default_participant_id()

    participant_role =
      Keyword.get(parsed, :participant_role) || Map.get(config, "participant_role") ||
        "coordinator"

    authority_level =
      Keyword.get(parsed, :authority_level) || Map.get(config, "authority_level") || "binding"

    %{
      participant_id: participant_id,
      participant_role: participant_role,
      authority_level: authority_level
    }
  end

  defp session_start_opts(parsed, config, room_id, identity_opts) do
    [
      room_id: room_id,
      api_base_url: api_base_url(parsed, config),
      poll_interval_ms:
        JidoHiveClient.Polling.normalize_interval_ms(
          Keyword.get(parsed, :poll_interval_ms) || Map.get(config, "poll_interval_ms")
        ),
      participant_id: identity_opts.participant_id,
      participant_role: identity_opts.participant_role,
      participant_kind: "human"
    ]
  end

  defp submit_chat_attrs(parsed, identity_opts, text) do
    %{
      text: text,
      authority_level: identity_opts.authority_level,
      participant_id: identity_opts.participant_id,
      participant_role: identity_opts.participant_role
    }
    |> maybe_put(:selected_context_id, parsed[:selected_context_id])
    |> maybe_put(:selected_context_object_type, parsed[:selected_context_object_type])
    |> maybe_put(:selected_relation, parsed[:selected_relation])
  end

  defp room_run_opts(parsed) do
    []
    |> maybe_put_integer_option(:max_assignments, parsed[:max_assignments])
    |> maybe_put_integer_option(:assignment_timeout_ms, parsed[:assignment_timeout_ms])
    |> maybe_put_integer_option(:request_timeout_ms, parsed[:request_timeout_ms])
    |> maybe_put_integer_option(:connect_timeout_ms, parsed[:connect_timeout_ms])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_integer_option(opts, _key, nil), do: opts
  defp maybe_put_integer_option(opts, _key, value) when not is_integer(value), do: opts
  defp maybe_put_integer_option(opts, key, value), do: Keyword.put(opts, key, value)

  defp truncate(value, max_length) when is_binary(value) and byte_size(value) <= max_length,
    do: value

  defp truncate(value, max_length) when is_binary(value),
    do: value |> String.slice(0, max_length - 1) |> Kernel.<>("…")

  defp shutdown_session(embedded_module, session) do
    cond do
      function_exported?(embedded_module, :shutdown, 1) ->
        embedded_module.shutdown(session)

      is_pid(session) ->
        Process.exit(session, :shutdown)
        :ok

      true ->
        :ok
    end
  end

  defp default_participant_id do
    {:ok, hostname} = :inet.gethostname()
    "human-#{List.to_string(hostname)}"
  end

  defp maybe_ensure_initialized(operator_module) do
    if function_exported?(operator_module, :ensure_initialized, 0) do
      :ok = operator_module.ensure_initialized()
    else
      :ok
    end
  end

  defp normalize_output(value) when is_map(value) do
    Map.new(value, fn {key, nested} ->
      {to_string(key), normalize_output(nested)}
    end)
  end

  defp normalize_output(value) when is_list(value), do: Enum.map(value, &normalize_output/1)
  defp normalize_output(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_output(value), do: value

  defp wrap_operation_result(prefix, result) do
    normalize_output(%{
      operation_id: Operation.new_id(prefix),
      result: result
    })
  end
end
