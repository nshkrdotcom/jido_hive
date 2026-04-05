defmodule JidoHiveServer.Collaboration.Schema.RoomEvent do
  @moduledoc false

  @type t :: %__MODULE__{
          event_id: String.t(),
          room_id: String.t(),
          type: atom(),
          payload: map(),
          causation_id: String.t() | nil,
          correlation_id: String.t() | nil,
          recorded_at: DateTime.t()
        }

  defstruct [
    :event_id,
    :room_id,
    :type,
    :payload,
    :causation_id,
    :correlation_id,
    :recorded_at
  ]

  @required_fields [:event_id, :room_id, :type, :payload, :recorded_at]

  @spec new(map()) :: {:ok, t()} | {:error, {:missing_field, atom()}}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs) do
      {:ok,
       %__MODULE__{
         event_id: attrs[:event_id] || attrs["event_id"],
         room_id: attrs[:room_id] || attrs["room_id"],
         type: atom_value(attrs[:type] || attrs["type"]),
         payload: attrs[:payload] || attrs["payload"],
         causation_id: attrs[:causation_id] || attrs["causation_id"],
         correlation_id: attrs[:correlation_id] || attrs["correlation_id"],
         recorded_at: attrs[:recorded_at] || attrs["recorded_at"]
       }}
    end
  end

  defp validate_required(attrs) do
    Enum.find_value(@required_fields, :ok, fn field ->
      case attrs[field] || attrs[Atom.to_string(field)] do
        nil -> {:error, {:missing_field, field}}
        _value -> nil
      end
    end)
  end

  defp atom_value(value) when is_binary(value), do: String.to_atom(value)
  defp atom_value(value), do: value
end
