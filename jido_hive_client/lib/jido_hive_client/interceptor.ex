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

    %{
      "room_id" => value(attrs, :room_id),
      "assignment_id" => value(attrs, :assignment_id),
      "participant_id" => value(attrs, :participant_id),
      "participant_role" => value(attrs, :participant_role) || "collaborator",
      "participant_kind" => value(attrs, :participant_kind) || "human",
      "target_id" => value(attrs, :target_id),
      "capability_id" => value(attrs, :capability_id),
      "contribution_type" => intercepted.contribution_type,
      "authority_level" => intercepted.authority_level,
      "summary" => intercepted.summary,
      "context_objects" => intercepted.context_objects,
      "artifacts" => intercepted.evidence_refs,
      "events" => [
        %{
          "event_type" => "chat.message",
          "body" => intercepted.chat_text,
          "tags" => intercepted.tags
        }
      ],
      "execution" => %{
        "status" => "completed",
        "backend" => backend_name(intercepted.raw_backend_output),
        "interceptor" => "mock_or_local"
      },
      "status" => "completed"
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_backend({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_backend(module) when is_atom(module), do: {module, []}
  defp normalize_backend(_other), do: {Mock, []}

  defp backend_name(%{"backend" => backend}) when is_binary(backend), do: backend
  defp backend_name(%{backend: backend}) when is_binary(backend), do: backend
  defp backend_name(_other), do: "unknown"

  defp value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
