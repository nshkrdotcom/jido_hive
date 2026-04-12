defmodule JidoHiveServer.Collaboration.Schema.Participant do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          room_id: String.t(),
          kind: String.t(),
          handle: String.t(),
          meta: map(),
          joined_at: DateTime.t()
        }

  defstruct [:id, :room_id, :kind, :handle, :meta, :joined_at]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    with {:ok, id} <- required_string(attrs, "id"),
         {:ok, room_id} <- required_string(attrs, "room_id"),
         {:ok, kind} <- required_string(attrs, "kind"),
         {:ok, handle} <- required_string(attrs, "handle") do
      {:ok,
       %__MODULE__{
         id: id,
         room_id: room_id,
         kind: kind,
         handle: handle,
         meta: map_value(attrs, "meta"),
         joined_at: datetime_value(attrs, "joined_at", now)
       }}
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = participant) do
    %{
      id: participant.id,
      room_id: participant.room_id,
      kind: participant.kind,
      handle: participant.handle,
      meta: participant.meta,
      joined_at: participant.joined_at
    }
  end

  defp required_string(attrs, key) do
    case optional_string(attrs, key) do
      nil -> {:error, {:missing_field, key}}
      value -> {:ok, value}
    end
  end

  defp optional_string(attrs, key) do
    case value(attrs, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _other ->
        nil
    end
  end

  defp map_value(attrs, key) do
    case value(attrs, key) do
      %{} = value -> value
      _other -> %{}
    end
  end

  defp datetime_value(attrs, key, default) do
    case value(attrs, key) do
      %DateTime{} = value ->
        value

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> datetime
          _other -> default
        end

      _other ->
        default
    end
  end

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
