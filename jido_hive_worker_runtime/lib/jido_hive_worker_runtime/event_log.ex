defmodule JidoHiveWorkerRuntime.EventLog do
  @moduledoc false

  @default_limit 200
  @schema_version "jido_hive/client_event.v1"

  defstruct limit: @default_limit, next_sequence: 1, entries: []

  @type event :: %{
          event_id: String.t(),
          source: atom(),
          topic: String.t(),
          type: String.t(),
          room_id: String.t() | nil,
          assignment_id: String.t() | nil,
          payload: map(),
          schema_version: String.t(),
          timestamp: DateTime.t(),
          sequence: pos_integer()
        }

  @type t :: %__MODULE__{
          limit: pos_integer(),
          next_sequence: pos_integer(),
          entries: [event()]
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{limit: normalize_limit(Keyword.get(opts, :limit, @default_limit))}
  end

  @spec append(t(), map()) :: {t(), event()}
  def append(%__MODULE__{} = log, attrs) when is_map(attrs) do
    entry = %{
      event_id: Map.get(attrs, :event_id, "client-event-#{log.next_sequence}"),
      source: Map.get(attrs, :source, :client),
      topic: Map.get(attrs, :topic, "client.runtime"),
      type: normalize_type(Map.get(attrs, :type, "client.runtime.changed")),
      room_id: Map.get(attrs, :room_id),
      assignment_id: Map.get(attrs, :assignment_id),
      payload: normalize_payload(Map.get(attrs, :payload, %{})),
      schema_version: Map.get(attrs, :schema_version, @schema_version),
      timestamp: Map.get(attrs, :timestamp, DateTime.utc_now()),
      sequence: log.next_sequence
    }

    entries =
      log.entries
      |> Kernel.++([entry])
      |> Enum.take(-log.limit)

    {%{log | entries: entries, next_sequence: log.next_sequence + 1}, entry}
  end

  @spec list(t(), keyword()) :: [event()]
  def list(%__MODULE__{} = log, opts \\ []) do
    after_cursor = Keyword.get(opts, :after)
    limit = Keyword.get(opts, :limit)

    entries =
      case after_cursor do
        nil -> log.entries
        cursor -> Enum.filter(log.entries, &entry_after?(&1, cursor, log.entries))
      end

    case limit do
      value when is_integer(value) and value >= 0 -> Enum.take(entries, value)
      _other -> entries
    end
  end

  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp normalize_limit(_other), do: @default_limit

  defp normalize_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_type(type) when is_binary(type), do: type
  defp normalize_type(_other), do: "client.runtime.changed"

  defp normalize_payload(payload) when is_map(payload), do: payload
  defp normalize_payload(_other), do: %{}

  defp entry_after?(entry, cursor, entries) when is_binary(cursor) do
    case Integer.parse(cursor) do
      {sequence, ""} ->
        entry.sequence > sequence

      _other ->
        case Enum.find(entries, &(&1.event_id == cursor)) do
          %{} = matched -> entry.sequence > matched.sequence
          nil -> true
        end
    end
  end

  defp entry_after?(entry, cursor, _entries) when is_integer(cursor), do: entry.sequence > cursor
  defp entry_after?(_entry, _cursor, _entries), do: true
end
