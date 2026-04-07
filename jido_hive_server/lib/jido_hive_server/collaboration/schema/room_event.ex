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
    with :ok <- validate_required(attrs),
         {:ok, type} <- atom_value(attrs[:type] || attrs["type"]) do
      {:ok,
       %__MODULE__{
         event_id: attrs[:event_id] || attrs["event_id"],
         room_id: attrs[:room_id] || attrs["room_id"],
         type: type,
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

  defp atom_value(value) when is_atom(value), do: {:ok, value}
  defp atom_value("room_created"), do: {:ok, :room_created}
  defp atom_value("assignment_opened"), do: {:ok, :assignment_opened}
  defp atom_value("contribution_recorded"), do: {:ok, :contribution_recorded}
  defp atom_value("contradiction_detected"), do: {:ok, :contradiction_detected}
  defp atom_value("downstream_invalidated"), do: {:ok, :downstream_invalidated}
  defp atom_value("assignment_abandoned"), do: {:ok, :assignment_abandoned}
  defp atom_value("runtime_state_changed"), do: {:ok, :runtime_state_changed}
  defp atom_value(_value), do: {:error, {:invalid_field, :type}}
end
