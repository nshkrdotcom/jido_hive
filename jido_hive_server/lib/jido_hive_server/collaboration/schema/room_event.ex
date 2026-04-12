defmodule JidoHiveServer.Collaboration.Schema.RoomEvent do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          room_id: String.t(),
          sequence: non_neg_integer(),
          type: atom(),
          data: map(),
          inserted_at: DateTime.t()
        }

  defstruct [:id, :room_id, :sequence, :type, :data, :inserted_at]

  @canonical_types [
    :room_created,
    :room_status_changed,
    :room_phase_changed,
    :participant_joined,
    :participant_left,
    :assignment_created,
    :assignment_completed,
    :assignment_expired,
    :contribution_submitted
  ]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    with {:ok, id} <- required_string(attrs, "id"),
         {:ok, room_id} <- required_string(attrs, "room_id"),
         {:ok, sequence} <- required_non_neg_integer(attrs, "sequence"),
         {:ok, type} <- event_type(attrs) do
      {:ok,
       %__MODULE__{
         id: id,
         room_id: room_id,
         sequence: sequence,
         type: type,
         data: map_value(attrs, "data"),
         inserted_at: datetime_value(attrs, "inserted_at", now)
       }}
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      id: event.id,
      room_id: event.room_id,
      sequence: event.sequence,
      type: event.type,
      data: event.data,
      inserted_at: event.inserted_at
    }
  end

  @spec canonical_type?(atom()) :: boolean()
  def canonical_type?(type), do: type in @canonical_types

  defp event_type(attrs), do: atom_value(value(attrs, "type"))

  defp required_string(attrs, key) do
    case optional_string(attrs, key) do
      nil -> {:error, {:missing_field, key}}
      value -> {:ok, value}
    end
  end

  defp required_non_neg_integer(attrs, key) do
    case integer_value(attrs, key) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _other -> {:error, {:missing_field, key}}
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

  defp atom_value(value) when is_atom(value) and value in @canonical_types, do: {:ok, value}

  defp atom_value(value) when is_binary(value) do
    atom =
      try do
        String.to_existing_atom(value)
      rescue
        ArgumentError -> nil
      end

    if atom in @canonical_types, do: {:ok, atom}, else: {:error, {:invalid_field, "type"}}
  end

  defp atom_value(_value), do: {:error, {:invalid_field, "type"}}

  defp integer_value(attrs, key) do
    case value(attrs, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _other -> nil
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
