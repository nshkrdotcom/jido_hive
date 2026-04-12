defmodule JidoHiveClient.Operator do
  @moduledoc """
  Headless operator API shared by the CLI, scripts, and interactive clients.
  """

  alias JidoHiveClient.CanonicalTransport
  alias JidoHiveClient.Operator.{Config, HTTP}

  @channels ~w[github notion]
  @default_run_assignment_timeout_ms 180_000

  @spec ensure_initialized() :: :ok
  def ensure_initialized, do: Config.ensure_initialized()

  @spec config_dir() :: String.t()
  def config_dir, do: Config.config_dir()

  @spec load_config() :: map()
  def load_config, do: Config.load()

  @spec list_saved_rooms(String.t()) :: [String.t()]
  def list_saved_rooms(api_base_url) when is_binary(api_base_url),
    do: Config.load_rooms(api_base_url)

  @spec add_saved_room(String.t(), String.t()) :: :ok | {:error, term()}
  def add_saved_room(room_id, api_base_url) when is_binary(room_id) and is_binary(api_base_url) do
    Config.add_room(room_id, api_base_url)
  end

  @spec remove_saved_room(String.t(), String.t()) :: :ok | {:error, term()}
  def remove_saved_room(room_id, api_base_url)
      when is_binary(room_id) and is_binary(api_base_url) do
    Config.remove_room(room_id, api_base_url)
  end

  @spec credentials_path() :: String.t()
  def credentials_path, do: Config.credentials_path()

  @spec store_auth_credential(String.t(), map()) :: :ok | {:error, term()}
  def store_auth_credential(channel, credential) when is_binary(channel) and is_map(credential) do
    next_credentials =
      Config.load_credentials()
      |> Map.put(channel, stringify_keys(credential))

    Config.write_credentials(next_credentials)
  end

  @spec load_auth_state(String.t() | nil, String.t() | nil, module()) :: map()
  def load_auth_state(api_base_url, subject, http_module \\ HTTP)

  def load_auth_state(api_base_url, subject, http_module)
      when is_binary(api_base_url) and api_base_url != "" and is_binary(subject) and subject != "" do
    credentials = Config.load_credentials()

    Enum.into(@channels, %{}, fn channel ->
      {channel, fetch_remote_auth_state(api_base_url, subject, channel, http_module, credentials)}
    end)
  end

  def load_auth_state(_api_base_url, _subject, _http_module) do
    credentials = Config.load_credentials()

    Enum.into(@channels, %{}, fn channel ->
      {channel, local_auth_state(channel, credentials)}
    end)
  end

  @spec list_room_events(String.t(), String.t(), keyword()) ::
          {:ok, %{entries: list(map()), next_cursor: String.t() | nil}} | {:error, term()}
  def list_room_events(api_base_url, room_id, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_list(opts) do
    http_opts =
      []
      |> Keyword.put(:lane, Keyword.get(opts, :lane, :operator_events))
      |> maybe_put_option(:operation_id, Keyword.get(opts, :operation_id))

    with {:ok, %{"data" => events, "meta" => meta}} when is_list(events) <-
           HTTP.get(api_base_url, "/rooms/#{room_id}/events#{after_query(opts)}", http_opts) do
      {:ok,
       %{
         entries: CanonicalTransport.event_entries(events),
         next_cursor: CanonicalTransport.next_cursor(Map.get(meta, "next_after_sequence"))
       }}
    end
  end

  @spec fetch_room(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch_room(api_base_url, room_id, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_list(opts) do
    http_opts =
      []
      |> Keyword.put(:lane, Keyword.get(opts, :lane, :operator_room))
      |> maybe_put_option(:operation_id, Keyword.get(opts, :operation_id))

    with {:ok, room_resource} <- fetch_room_resource(api_base_url, room_id, http_opts),
         {:ok, assignments} <- fetch_assignments(api_base_url, room_id, http_opts),
         {:ok, contributions} <- fetch_all_contributions(api_base_url, room_id, http_opts) do
      {:ok, CanonicalTransport.room_snapshot(room_resource, assignments, contributions)}
    end
  end

  @spec submit_contribution(String.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def submit_contribution(api_base_url, room_id, payload, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_map(payload) and is_list(opts) do
    http_opts =
      []
      |> Keyword.put(:lane, Keyword.get(opts, :lane, :operator_contribution))
      |> maybe_put_option(:operation_id, Keyword.get(opts, :operation_id))
      |> maybe_put_option(:request_timeout_ms, Keyword.get(opts, :request_timeout_ms))
      |> maybe_put_option(:connect_timeout_ms, Keyword.get(opts, :connect_timeout_ms))

    canonical_payload = %{"data" => CanonicalTransport.contribution_payload(payload, room_id)}

    unwrap_data(
      HTTP.post(api_base_url, "/rooms/#{room_id}/contributions", canonical_payload, http_opts)
    )
  end

  @spec create_room(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_room(api_base_url, payload) when is_binary(api_base_url) and is_map(payload) do
    with {:ok, room_resource} <-
           api_base_url
           |> HTTP.post("/rooms", %{"data" => canonical_room_payload(payload)})
           |> unwrap_data() do
      {:ok, CanonicalTransport.room_snapshot(room_resource, [], [])}
    end
  end

  @spec start_room_run_operation(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def start_room_run_operation(api_base_url, room_id, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_list(opts) do
    assignment_timeout_ms =
      Keyword.get(opts, :assignment_timeout_ms, @default_run_assignment_timeout_ms)

    http_opts =
      []
      |> Keyword.put(:lane, Keyword.get(opts, :lane, :room_run_control))
      |> Keyword.put(:operation_id, Keyword.get(opts, :operation_id))
      |> maybe_put_option(:request_timeout_ms, Keyword.get(opts, :request_timeout_ms))
      |> maybe_put_option(:connect_timeout_ms, Keyword.get(opts, :connect_timeout_ms))

    payload =
      %{}
      |> maybe_put_string("client_operation_id", Keyword.get(opts, :client_operation_id))
      |> maybe_put_integer("max_assignments", Keyword.get(opts, :max_assignments))
      |> maybe_put_integer("assignment_timeout_ms", assignment_timeout_ms)
      |> Map.put("until", normalize_run_until(Keyword.get(opts, :until)))

    with {:ok, %{"data" => %{"run" => run}}} <-
           HTTP.post(api_base_url, "/rooms/#{room_id}/runs", %{"data" => payload}, http_opts) do
      {:ok, CanonicalTransport.run_operation(run, Keyword.get(opts, :client_operation_id))}
    end
  end

  @spec fetch_room_run_operation(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def fetch_room_run_operation(api_base_url, room_id, operation_id, opts \\ [])
      when is_binary(api_base_url) and is_binary(room_id) and is_binary(operation_id) and
             is_list(opts) do
    http_opts =
      []
      |> Keyword.put(:lane, Keyword.get(opts, :lane, :room_run_status))
      |> maybe_put_option(:operation_id, Keyword.get(opts, :operation_id))
      |> maybe_put_option(:request_timeout_ms, Keyword.get(opts, :request_timeout_ms))
      |> maybe_put_option(:connect_timeout_ms, Keyword.get(opts, :connect_timeout_ms))

    with {:ok, %{"data" => %{"run" => run}}} <-
           HTTP.get(api_base_url, "/rooms/#{room_id}/runs/#{operation_id}", http_opts) do
      {:ok, CanonicalTransport.run_operation(run)}
    end
  end

  @spec list_targets(String.t()) :: {:ok, list(map())} | {:error, term()}
  def list_targets(api_base_url) when is_binary(api_base_url) do
    unwrap_data_list(HTTP.get(api_base_url, "/targets"))
  end

  @spec list_policies(String.t()) :: {:ok, list(map())} | {:error, term()}
  def list_policies(api_base_url) when is_binary(api_base_url) do
    unwrap_data_list(HTTP.get(api_base_url, "/policies"))
  end

  @spec start_install(String.t(), String.t(), String.t(), list(String.t())) ::
          {:ok, map()} | {:error, term()}
  def start_install(api_base_url, channel, subject, scopes)
      when is_binary(api_base_url) and is_binary(channel) and is_binary(subject) and
             is_list(scopes) do
    payload = %{
      "subject" => subject,
      "tenant_id" => Map.get(load_config(), "tenant_id", "workspace-local"),
      "scopes" => scopes
    }

    unwrap_data(HTTP.post(api_base_url, "/connectors/#{channel}/installs", payload))
  end

  @spec complete_install(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def complete_install(api_base_url, install_id, subject, access_token)
      when is_binary(api_base_url) and is_binary(install_id) and is_binary(subject) and
             is_binary(access_token) do
    payload = %{"subject" => subject, "access_token" => access_token}

    unwrap_data(HTTP.post(api_base_url, "/connectors/installs/#{install_id}/complete", payload))
  end

  @spec start_device_flow(String.t()) :: {:ok, map()} | {:error, term()}
  def start_device_flow(channel) when channel in @channels do
    {:ok,
     %{
       channel: channel,
       user_code: random_code(),
       verification_uri: "https://auth.#{channel}.example/device"
     }}
  end

  def start_device_flow(channel), do: {:error, {:unsupported_channel, channel}}

  @spec connection_id(map(), String.t()) :: String.t() | nil
  def connection_id(auth_state, channel) when is_map(auth_state) and is_binary(channel) do
    case Map.get(auth_state, channel) do
      %{connection_id: connection_id} when is_binary(connection_id) and connection_id != "" ->
        connection_id

      %{"connection_id" => connection_id} when is_binary(connection_id) and connection_id != "" ->
        connection_id

      _other ->
        nil
    end
  end

  @spec auth_status(map(), String.t()) :: :cached | :missing | :pending
  def auth_status(auth_state, channel) when is_map(auth_state) and is_binary(channel) do
    case Map.get(auth_state, channel) do
      %{status: status} when status in [:cached, :missing, :pending] -> status
      %{"status" => status} when status in [:cached, :missing, :pending] -> status
      _other -> :missing
    end
  end

  defp fetch_remote_auth_state(api_base_url, subject, channel, http_module, credentials) do
    path = "/connectors/#{channel}/connections?subject=#{URI.encode_www_form(subject)}"
    local = local_auth_state(channel, credentials)

    case http_module.get(api_base_url, path) do
      {:ok, %{"data" => connections}} when is_list(connections) ->
        merge_remote_and_local(remote_auth_state(connections), local)

      _other ->
        local
    end
  end

  defp remote_auth_state(connections) do
    cond do
      connection = latest_connection(connections, &connected?/1) ->
        %{
          connection_id: Map.get(connection, "connection_id"),
          source: :server,
          state: Map.get(connection, "state", "connected"),
          status: :cached
        }

      connection = latest_connection(connections, &(not connected?(&1))) ->
        %{
          connection_id: Map.get(connection, "connection_id"),
          source: :server,
          state: Map.get(connection, "state"),
          status: :pending
        }

      true ->
        %{
          connection_id: nil,
          source: :server,
          state: nil,
          status: :missing
        }
    end
  end

  defp local_auth_state(channel, credentials) do
    case Map.get(credentials, channel) do
      %{"connection_id" => connection_id} = credential
      when is_binary(connection_id) and connection_id != "" ->
        if expired?(credential) do
          missing_auth_state()
        else
          %{
            connection_id: connection_id,
            source: :local,
            state: "cached",
            status: :cached
          }
        end

      _other ->
        missing_auth_state()
    end
  end

  defp latest_connection(connections, predicate) do
    connections
    |> Enum.filter(predicate)
    |> Enum.max_by(&connection_timestamp/1, fn -> nil end)
  end

  defp connected?(connection), do: Map.get(connection, "state") == "connected"

  defp connection_timestamp(connection) do
    Map.get(connection, "updated_at") || Map.get(connection, "inserted_at") || ""
  end

  defp missing_auth_state do
    %{
      connection_id: nil,
      source: :missing,
      state: nil,
      status: :missing
    }
  end

  defp merge_remote_and_local(%{status: :cached} = remote, _local), do: remote
  defp merge_remote_and_local(_remote, %{status: :cached} = local), do: local
  defp merge_remote_and_local(remote, _local), do: remote

  defp expired?(%{"expires_at" => expires_at}) when is_binary(expires_at) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, datetime, _offset} -> DateTime.compare(datetime, DateTime.utc_now()) == :lt
      _other -> false
    end
  end

  defp expired?(_credential), do: false

  defp random_code do
    4
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :upper)
    |> String.replace(~r/(....)(....)/, "\\1-\\2")
  end

  defp unwrap_data({:ok, %{"data" => data}}) when is_map(data), do: {:ok, data}
  defp unwrap_data({:ok, payload}), do: {:error, {:unexpected_payload, payload}}
  defp unwrap_data({:error, reason}), do: {:error, reason}

  defp unwrap_data_list({:ok, %{"data" => data}}) when is_list(data), do: {:ok, data}
  defp unwrap_data_list({:ok, payload}), do: {:error, {:unexpected_payload, payload}}
  defp unwrap_data_list({:error, reason}), do: {:error, reason}

  defp maybe_put_integer(map, _key, nil), do: map
  defp maybe_put_integer(map, _key, value) when not is_integer(value), do: map
  defp maybe_put_integer(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_string(map, _key, nil), do: map
  defp maybe_put_string(map, _key, value) when not is_binary(value), do: map
  defp maybe_put_string(map, _key, value) when value == "", do: map
  defp maybe_put_string(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_option(opts, _key, nil), do: opts
  defp maybe_put_option(opts, key, value), do: Keyword.put(opts, key, value)

  defp after_query(opts) do
    case Keyword.get(opts, :after) do
      after_cursor when is_binary(after_cursor) and after_cursor != "" ->
        "?after=#{URI.encode_www_form(after_cursor)}"

      after_cursor when is_integer(after_cursor) and after_cursor >= 0 ->
        "?after=#{after_cursor}"

      _other ->
        ""
    end
  end

  defp fetch_room_resource(api_base_url, room_id, http_opts) do
    with {:ok, %{"data" => room_resource}} when is_map(room_resource) <-
           HTTP.get(api_base_url, "/rooms/#{room_id}", http_opts) do
      {:ok, room_resource}
    end
  end

  defp fetch_assignments(api_base_url, room_id, http_opts) do
    with {:ok, %{"data" => assignments}} when is_list(assignments) <-
           HTTP.get(api_base_url, "/rooms/#{room_id}/assignments", http_opts) do
      {:ok, assignments}
    end
  end

  defp fetch_all_contributions(api_base_url, room_id, http_opts, after_sequence \\ 0, acc \\ [])

  defp fetch_all_contributions(api_base_url, room_id, http_opts, after_sequence, acc) do
    path =
      "/rooms/#{room_id}/contributions?limit=200&after_sequence=#{after_sequence}"

    with {:ok, %{"data" => entries, "meta" => meta}} when is_list(entries) <-
           HTTP.get(api_base_url, path, http_opts) do
      next_acc = acc ++ entries

      if Map.get(meta, "has_more") do
        fetch_all_contributions(
          api_base_url,
          room_id,
          http_opts,
          Map.get(meta, "next_after_sequence", after_sequence),
          next_acc
        )
      else
        {:ok, next_acc}
      end
    end
  end

  defp canonical_room_payload(payload) do
    payload = stringify_keys(payload)
    config = map_value(payload, "config")

    participants =
      payload
      |> list_value("participants")
      |> Enum.map(&canonical_participant_payload/1)

    %{}
    |> maybe_put_string("id", Map.get(payload, "id"))
    |> maybe_put_string("name", Map.get(payload, "name"))
    |> maybe_put_string("phase", Map.get(payload, "phase"))
    |> Map.put("config", config)
    |> Map.put("participants", participants)
  end

  defp canonical_participant_payload(participant) do
    participant = stringify_keys(participant)

    meta =
      %{}
      |> maybe_put("role", Map.get(participant, "participant_role"))
      |> maybe_put("authority_level", Map.get(participant, "authority_level"))
      |> maybe_put("target_id", Map.get(participant, "target_id"))
      |> maybe_put("capability_id", Map.get(participant, "capability_id"))
      |> maybe_put("runtime_driver", Map.get(participant, "runtime_driver"))
      |> maybe_put("provider", Map.get(participant, "provider"))
      |> maybe_put("workspace_root", Map.get(participant, "workspace_root"))
      |> maybe_put(
        "runtime_kind",
        case Map.get(participant, "participant_kind") do
          "runtime" -> "runtime"
          "agent" -> "agent"
          other -> other
        end
      )
      |> Map.merge(map_value(participant, "meta"))

    %{}
    |> maybe_put_string(
      "id",
      Map.get(participant, "id") || Map.get(participant, "participant_id")
    )
    |> maybe_put_string(
      "kind",
      canonical_kind(Map.get(participant, "kind") || Map.get(participant, "participant_kind"))
    )
    |> maybe_put_string(
      "handle",
      Map.get(participant, "handle") || Map.get(participant, "participant_id")
    )
    |> Map.put("meta", meta)
  end

  defp canonical_kind("runtime"), do: "agent"
  defp canonical_kind(nil), do: "human"
  defp canonical_kind(kind), do: kind

  defp normalize_run_until(%{"kind" => _kind} = until), do: until
  defp normalize_run_until(%{kind: kind} = until) when is_binary(kind), do: stringify_keys(until)
  defp normalize_run_until(_until), do: %{"kind" => "policy_complete"}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, _key, %{} = value) when map_size(value) == 0, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp map_value(map, key) when is_map(map) do
    case Map.get(map, key) do
      %{} = value -> value
      _other -> %{}
    end
  end

  defp list_value(map, key) when is_map(map) do
    case Map.get(map, key) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
