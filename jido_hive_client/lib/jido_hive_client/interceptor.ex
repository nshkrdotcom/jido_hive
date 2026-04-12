defmodule JidoHiveClient.Interceptor do
  @moduledoc false

  alias JidoHiveClient.AgentBackends.Mock
  alias JidoHiveClient.{ChatInput, InterceptedContribution}

  @spec extract(ChatInput.t() | map() | keyword(), keyword()) ::
          {:ok, InterceptedContribution.t()} | {:error, term()}
  def extract(chat_input_or_attrs, opts \\ []) do
    {backend, backend_opts} = normalize_backend(Keyword.get(opts, :backend, Mock))

    case ChatInput.new(chat_input_or_attrs) do
      {:ok, chat_input} ->
        case backend.extract_contribution(chat_input, backend_opts) do
          {:ok, intercepted} -> InterceptedContribution.new(intercepted)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec to_contribution(InterceptedContribution.t() | map(), map()) :: map()
  def to_contribution(intercepted_contribution, attrs) when is_map(attrs) do
    intercepted =
      case InterceptedContribution.new(intercepted_contribution) do
        {:ok, contribution} ->
          contribution

        {:error, reason} ->
          raise ArgumentError, "invalid intercepted contribution: #{inspect(reason)}"
      end

    payload =
      %{}
      |> maybe_put("summary", intercepted.summary)
      |> maybe_put("context_objects", intercepted.context_objects)
      |> maybe_put("artifacts", intercepted.evidence_refs)

    meta =
      %{}
      |> maybe_put("participant_role", value(attrs, :participant_role) || "collaborator")
      |> maybe_put("participant_kind", value(attrs, :participant_kind) || "human")
      |> maybe_put("target_id", value(attrs, :target_id))
      |> maybe_put("capability_id", value(attrs, :capability_id))
      |> maybe_put("authority_level", intercepted.authority_level)
      |> maybe_put("events", [
        %{
          "event_type" => "chat.message",
          "body" => intercepted.chat_text,
          "tags" => intercepted.tags
        }
      ])
      |> maybe_put("execution", %{
        "status" => "completed",
        "backend" => backend_name(intercepted.raw_backend_output),
        "interceptor" => "mock_or_local"
      })
      |> Map.put("status", "completed")

    %{}
    |> maybe_put("room_id", value(attrs, :room_id))
    |> maybe_put("assignment_id", value(attrs, :assignment_id))
    |> maybe_put("participant_id", value(attrs, :participant_id))
    |> Map.put("kind", intercepted.contribution_type)
    |> Map.put("payload", payload)
    |> Map.put("meta", meta)
  end

  defp normalize_backend({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_backend(module) when is_atom(module), do: {module, []}
  defp normalize_backend(_other), do: {Mock, []}

  defp backend_name(%{"backend" => backend}) when is_binary(backend), do: backend
  defp backend_name(%{backend: backend}) when is_binary(backend), do: backend
  defp backend_name(_other), do: "unknown"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, _key, %{} = value) when map_size(value) == 0, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
