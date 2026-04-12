defmodule JidoHiveServer.Collaboration.Schema.Contribution do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          room_id: String.t(),
          assignment_id: String.t() | nil,
          participant_id: String.t(),
          kind: String.t(),
          payload: map(),
          meta: map(),
          inserted_at: DateTime.t()
        }

  defstruct [:id, :room_id, :assignment_id, :participant_id, :kind, :payload, :meta, :inserted_at]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    with {:ok, id} <- required_string(attrs, "id"),
         {:ok, room_id} <- required_string(attrs, "room_id"),
         {:ok, participant_id} <- required_string(attrs, "participant_id"),
         {:ok, kind} <- required_string(attrs, "kind") do
      {:ok,
       %__MODULE__{
         id: id,
         room_id: room_id,
         assignment_id: optional_string(attrs, "assignment_id"),
         participant_id: participant_id,
         kind: kind,
         payload: map_value(attrs, "payload"),
         meta: map_value(attrs, "meta"),
         inserted_at: datetime_value(attrs, "inserted_at", now)
       }}
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = contribution) do
    %{
      id: contribution.id,
      room_id: contribution.room_id,
      assignment_id: contribution.assignment_id,
      participant_id: contribution.participant_id,
      kind: contribution.kind,
      payload: contribution.payload,
      meta: contribution.meta,
      inserted_at: contribution.inserted_at
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

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
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
end
